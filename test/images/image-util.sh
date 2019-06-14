#!/usr/bin/env bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

TASK=$1
IMAGE=$2

KUBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${KUBE_ROOT}/hack/lib/util.sh"

# Mapping of go ARCH to actual architectures shipped part of multiarch/qemu-user-static project
declare -A QEMUARCHS=( ["amd64"]="x86_64" ["arm"]="arm" ["arm64"]="aarch64" ["ppc64le"]="ppc64le" ["s390x"]="s390x" )

# Returns list of all supported architectures from BASEIMAGE file
listOsArchs() {
  cut -d "=" -f 1 "${IMAGE}"/BASEIMAGE
}

# Returns baseimage need to used in Dockerfile for any given architecture
getBaseImage() {
  os_name=$1
  arch=$2
  echo $(grep "${os_name}/${arch}=" BASEIMAGE | cut -d= -f2)
}

# This function will build test image for all the architectures
# mentioned in BASEIMAGE file. In the absence of BASEIMAGE file,
# it will build for all the supported arch list - amd64, arm,
# arm64, ppc64le, s390x
build() {
  if [[ -f ${IMAGE}/BASEIMAGE ]]; then
    os_archs=$(listOsArchs)
  else
    # prepend linux/ to the QEMUARCHS items.
    os_archs=$(printf 'linux/%s\n' "${!QEMUARCHS[@]}")
  fi

  kube::util::ensure-gnu-sed

  for os_arch in ${os_archs}; do
    if [[ $os_arch =~ .*/.* ]]; then
      os_name=$(echo $os_arch | cut -d "/" -f 1)
      arch=$(echo $os_arch | cut -d "/" -f 2)
    else
      echo "The BASEIMAGE file for the ${IMAGE} image is not properly formatted. Expected entries to start with 'os/arch', found '${os_arch}' instead."
      exit 1
    fi

    echo "Building image for ${IMAGE} OS/ARCH: ${os_name}/${arch}..."

    # Create a temporary directory for every architecture and copy the image content
    # and build the image from temporary directory
    mkdir -p "${KUBE_ROOT}"/_tmp
    temp_dir=$(mktemp -d "${KUBE_ROOT}"/_tmp/test-images-build.XXXXXX)
    kube::util::trap_add "rm -rf ${temp_dir}" EXIT

    cp -r "${IMAGE}"/* "${temp_dir}"
    if [[ -f ${IMAGE}/Makefile ]]; then
      # make bin will take care of all the prerequisites needed
      # for building the docker image
      make -C "${IMAGE}" bin OS="${os_name}" ARCH="${arch}" TARGET="${temp_dir}"
    fi
    pushd "${temp_dir}"

    # we might have to build multiple images with the same name, but different versions.
    # in this case, they will have different folders. in order to keep the same name, they will
    # have an ALIAS file with the actual image name.
    IMAGE_NAME=$(cat ALIAS 2> /dev/null || echo "${IMAGE}")
    # image tag
    TAG=$(<VERSION)

    if [[ -f BASEIMAGE ]]; then
      BASEIMAGE=$(getBaseImage "${os_name}" "${arch}" | ${SED} "s|REGISTRY|${REGISTRY}|g")

      # NOTE(claudiub): Some Windows images might require their own Dockerfile
      # while simpler ones will not. If we're building for Windows, check if
      # "Dockerfile_windows" exists or not.
      dockerfile_name="Dockerfile"
      if [[ "$os_name" = "windows" && -f "Dockerfile_windows" ]]; then
        dockerfile_name="Dockerfile_windows"
      fi

      ${SED} -i "s|BASEIMAGE|${BASEIMAGE}|g" $dockerfile_name
      ${SED} -i "s|BASEARCH|${arch}|g" $dockerfile_name
    fi

    # copy the qemu-*-static binary to docker image to build the multi architecture image on x86 platform
    if [[ $(grep "CROSS_BUILD_" Dockerfile) ]]; then
      if [[ "${arch}" == "amd64" ]]; then
        ${SED} -i "/CROSS_BUILD_/d" Dockerfile
      else
        ${SED} -i "s|QEMUARCH|${QEMUARCHS[$arch]}|g" Dockerfile
        # Register qemu-*-static for all supported processors except the current one
        echo "Registering qemu-*-static binaries in the kernel"
        local sudo=""
        if [[ $(id -u) != 0 ]]; then
          sudo=sudo
        fi
        "${sudo}" "${KUBE_ROOT}/third_party/multiarch/qemu-user-static/register/register.sh" --reset
        curl -sSL https://github.com/multiarch/qemu-user-static/releases/download/"${QEMUVERSION}"/x86_64_qemu-"${QEMUARCHS[$arch]}"-static.tar.gz | tar -xz -C "${temp_dir}"
        # Ensure we don't get surprised by umask settings
        chmod 0755 "${temp_dir}/qemu-${QEMUARCHS[$arch]}-static"
        ${SED} -i "s/CROSS_BUILD_//g" Dockerfile
      fi
    fi

    if [[ "$os_name" = "linux" ]]; then
      docker build  -t "${REGISTRY}/${IMAGE_NAME}:${TAG}-${os_name}-${arch}" .
    elif [[ -v "REMOTE_DOCKER_URL" && ! -z "${REMOTE_DOCKER_URL}" ]]; then
      # NOTE(claudiub): We're using a remote Windows node to build the Windows Docker images.
      # The node requires TLS authentication, and thus it is expected that the
      # ca.pem, cert.pem, key.pem files can be found in the ~/.docker folder.
      docker  -H "${REMOTE_DOCKER_URL}" build  -t "${REGISTRY}/${IMAGE_NAME}:${TAG}-${os_name}-${arch}" -f $dockerfile_name .
    else
      echo "Cannot build the image '${IMAGE_NAME}' for ${os_name}/${arch}. REMOTE_DOCKER_URL should be set, containing the URL to a Windows docker daemon."
    fi

    popd
  done
}

docker_version_check() {
  # The reason for this version check is even though "docker manifest" command is available in 18.03, it does
  # not work properly in that version. So we insist on 18.06.0 or higher.
  docker_version=$(docker version --format '{{.Client.Version}}' | cut -d"-" -f1)
  if [[ ${docker_version} != 18.06.0 && ${docker_version} < 18.06.0 ]]; then
    echo "Minimum docker version 18.06.0 is required for creating and pushing manifest images[found: ${docker_version}]"
    exit 1
  fi
}

# This function will push the docker images
push() {
  docker_version_check
  TAG=$(<"${IMAGE}"/VERSION)
  if [[ -f ${IMAGE}/BASEIMAGE ]]; then
    os_archs=$(listOsArchs)
    # NOTE(claudiub): if the REMOTE_DOCKER_URL var is not set, or it is an empty string, we must skip
    # pushing the Windows image and including it into the manifest list.
    if [[ ((! -v "REMOTE_DOCKER_URL") || -z "${REMOTE_DOCKER_URL}") && -n "$(printf "%s\n" $os_archs | grep '^windows')" ]]; then
      echo "Skipping pushing the image '${IMAGE}' for Windows. REMOTE_DOCKER_URL should be set, containing the URL to a Windows docker daemon."
      os_archs=$(printf "%s\n" $os_archs | grep -v "^windows")
    fi
  else
    # prepend linux/ to the QEMUARCHS items.
    os_archs=$(printf 'linux/%s\n' "${!QEMUARCHS[@]}")
  fi
  for os_arch in ${os_archs}; do
    if [[ $os_arch =~ .*/.* ]]; then
      os_name=$(echo $os_arch | cut -d "/" -f 1)
      arch=$(echo $os_arch | cut -d "/" -f 2)
    else
      echo "The BASEIMAGE file for the ${IMAGE} image is not properly formatted. Expected entries to start with 'os/arch', found '${os_arch}' instead."
      exit 1
    fi

    if [[ "$os_name" = "linux" ]]; then
      docker push "${REGISTRY}/${IMAGE}:${TAG}-${os_name}-${arch}"
    else
      # NOTE(claudiub): We're pushing the image we built on the remote Windows node.
      docker -H "${REMOTE_DOCKER_URL}" push "${REGISTRY}/${IMAGE}:${TAG}-${os_name}-${arch}"
    fi
  done

  kube::util::ensure-gnu-sed

  # The manifest command is still experimental as of Docker 18.09.2
  export DOCKER_CLI_EXPERIMENTAL="enabled"
  # Make base_images list into image manifest. Eg: 'linux/amd64 linux/ppc64le' to '${REGISTRY}/${IMAGE_NAME}:${TAG}-linux-amd64 ${REGISTRY}/${IMAGE}:${TAG}-linux-ppc64le'
  manifest=$(echo "$base_images" | ${SED} "s~\/~-~g" | ${SED} -e "s~[^ ]*~$REGISTRY\/$IMAGE_NAME:$TAG\-&~g")
  docker manifest create --amend "${REGISTRY}/${IMAGE_NAME}:${TAG}" ${manifest}
  for base_image in ${base_images}; do
    if [[ $base_image =~ .*/.* ]]; then
      os_name=`echo $base_image | cut -d "/" -f 1`
      arch=`echo $base_image | cut -d "/" -f 2`
    fi
    docker manifest annotate --os "${os_name}" --arch "${arch}" "${REGISTRY}/${IMAGE_NAME}:${TAG}" "${REGISTRY}/${IMAGE_NAME}:${TAG}-${os_name}-${arch}"
  done
  docker manifest push --purge "${REGISTRY}/${IMAGE_NAME}:${TAG}"
}

# This function is for building the go code
bin() {
  for SRC in $@;
  do
  docker run --rm -it -v "${TARGET}:${TARGET}:Z" -v "${KUBE_ROOT}":/go/src/k8s.io/kubernetes:Z \
        golang:"${GOLANG_VERSION}" \
        /bin/bash -c "\
                cd /go/src/k8s.io/kubernetes/test/images/${SRC_DIR} && \
                CGO_ENABLED=0 GOARM=${GOARM} GOOS=${OS} GOARCH=${ARCH} go build -a -installsuffix cgo --ldflags '-w' -o ${TARGET}/${SRC} ./$(dirname "${SRC}")"
  done
}

shift

eval "${TASK}" "$@"
