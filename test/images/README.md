# Building Kubernetes test images

## Overview

All the images found here are used in Kubernetes tests that ensures its features and functionality.
The images are built and published as manifest lists, allowing multiarch and cross platoform support.

## Prerequisites

In order to build the docker test images, a Linux node is required. The node will require `make`
and `docker (version 18.06.0 or newer)`. Manifest lists were introduced in 18.03.0, but 18.06.0
is recommended in order to avoid certain issues.

The node must be able to push the images to the desired container registry. Depending on the
container registry, it might require a different authentication method. For dockerhub, this
can be done by running the command:

```bash
    docker login -u your-awesome-username -p anAwesomerPassword
```

Windows Container images are not built by default, since they cannot be built on Linux. For
that, a Windows node with Docker installed and configured for remote management is required.

### Windows node setup

In order to build the Windows container images, a node with Windows 10 or Windows Server 2019
with the latest updates installed is required. The node will have to have Docker installed,
preferably version 18.06.0 or newer.

Note which version of Docker is installed on the Windows node: Enterprise Edition, or
Community Edition. If it is EE, the container OS version and the host's OS version **must** match
in order to start the containers. Currently, the Windows Containers are built based on the
`mcr.microsoft.com/windows/servercore:ltsc2019` image.

Additionally, remote management must be configured for the node's Docker daemon. Exposing the
Docker daemon without requiring any authentication is not recommended, and thus, it must be
configured with TLS to ensure that only authorised people can interact with it. For this, the
following `powershell` script can be executed:

```powershell
    mkdir server
    mkdir client\.docker
    docker run --rm `
      -e SERVER_NAME=$(hostname) `
      -e IP_ADDRESSES=127.0.0.1,YOUR_LINUX_BUILD_NODE `
      -v "$(pwd)\server:c:\programdata\docker" `
      -v "$(pwd)\client\.docker:c:\users\containeradministrator\.docker" stefanscherer/dockertls-windows:1809
    docker run --rm `
      -e SERVER_NAME=$(hostname) `
      -e IP_ADDRESSES=127.0.0.1,YOUR_LINUX_BUILD_NODE `
      -v "c:\programdata\docker:c:\programdata\docker" `
      -v "$env:USERPROFILE\.docker:c:\users\containeradministrator\.docker" stefanscherer/dockertls-windows:1809
    # restart the Docker daemon.
    Restart-Service docker
```

For more information about the above commands, you can check [here](https://hub.docker.com/r/stefanscherer/dockertls-windows/).

A firewall rule to allow connections to the Docker daemon is necessary:

```powershell
    New-NetFirewallRule -DisplayName 'Docker SSL Inbound' -Profile @('Domain', 'Public', 'Private') -Direction Inbound -Action Allow -Protocol TCP -LocalPort 2376
```

The `ca.pem`, `cert.pem`, and `key.pem` files that can be found in `$env:USERPROFILE\.docker`
will have to copied to the `~/.docker/` on the Linux build node. After all this, the Linux
build node should be able to connect to the Windows build node:

```bash
    docker --tlsverify -H "$REMOTE_DOCKER_URL" version
```

For more information and troubleshooting about enabling Docker remote management, see
[here](https://docs.microsoft.com/en-us/virtualization/windowscontainers/management/manage_remotehost)

Finally, the Windows node must be able to push the built images to the desired registry. For
dockerhub, the following command can be executed:

```powershell
    docker login -u your-awesome-username -p anAwesomerPassword
```

## Building images

The images are built through `make`. Since some images (`busybox` ,`mounttest`, `test-webserver`)
are used as a base for other images, it is recommended to built them first.

An image can be built by simply running the command:

```bash
    make all WHAT=test-webserver
```

To build AND push an image, the following command can be used:

```bash
    make all-push WHAT=test-webserver
```

By default, the images will be tagged and pushed under the `gcr.io/kubernetes-e2e-test-images`
registry. That can changed by running this command instead:

```bash
    REGISTRY=foo_registry make all-push WHAT=test-webserver
```

In order to also include Windows Container images into the final manifest lists, the
`REMOTE_DOCKER_URL` argument will also have to be specified:

```bash
    REMOTE_DOCKER_URL=remote_docker_url REGISTRY=foo_registry make all-push WHAT=test-webserver
```

## Known issues and workarounds

`docker manifest create` fails due to permission denied on `/etc/docker/certs.d/gcr.io` (https://github.com/docker/for-linux/issues/396)
