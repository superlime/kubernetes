# Agnhost

## Overview

There are significant differences between Linux and Windows, especially in the way
something can be obtained or tested. For example, the DNS suffix list can be found in
`/etc/resolv.conf` on Linux, but on Windows, such file does not exist, the same
information could retrieved through other means. To combat those differences,
`agnhost` was created.

`agnhost` is an extendable CLI that behaves and outputs the same expected content,
no matter the underlying OS. The name itself reflects this idea, being a portmanteau
word of the words agnost and host.

The image was created for testing purposes, reducing the need for having different test
cases for the same tested behaviour.

## Usage

The `agnhost` binary has several subcommands which are can be used to test different
Kubernetes features; their behaviour and output is not affected by the underlying OS.

For example, let's consider the following `pod.yaml` file:

```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-agnhost
    spec:
      containers:
      - args:
        - dns-suffix
        image: gcr.io/kubernetes-e2e-test-images/agnhost:1.0
        name: agnhost
      dnsConfig:
        nameservers:
        - 1.1.1.1
        searches:
        - resolv.conf.local
      dnsPolicy: None
```

After we've used it to create a pod:

```console
    kubectl create -f pod.yaml
```

We can then check the container's output to see what is DNS suffix list the Pod was
configured with:

```console
    kubectl logs pod/test-agnhost
```

The output will be `resolv.conf.local`, as expected. Alternatively, the Pod could be
created with the `pause` argument instead, allowing us execute multiple commands:

```console
    kubectl exec test-agnhost -- /agnhost dns-suffix
    kubectl exec test-agnhost -- /agnhost dns-server-list
```

The `agnhost` binary is a CLI with the following subcommands:

### dns-server-list

It will output the host's configured DNS servers, separated by commas.

Usage:

```console
    kubectl exec test-agnhost -- /agnhost dns-server-list
```

### dns-suffix

It will output the host's configured DNS suffix list, separated by commas.

Usage:

```console
    kubectl exec test-agnhost -- /agnhost dns-suffix
```

### etc-hosts

It will output the contents of host's `hosts` file. This file's location is `/etc/hosts`
on Linux, while on Windows it is `C:/Windows/System32/drivers/etc/hosts`.

Usage:

```console
    kubectl exec test-agnhost -- /agnhost etc-hosts
```

### fake-gitserver

TBA

Usage:

```console
    kubectl exec test-agnhost -- /agnhost fake-gitserver
```

### help

Prints the binary's help menu. Additionally, it can be followed by another subcommand
in order to get more information about that subcommand, including its possible arguments.

Usage:

```console
    kubectl exec test-agnhost -- /agnhost help
```

### liveness

TBA

Usage:

```console
    kubectl exec test-agnhost -- /agnhost liveness
```

### logs-generator

The `logs-generator` subcommand is a tool to create predictable load on the logs delivery system.
It generates random lines with predictable format and predictable average length.
Each line can be later uniquely identified to ensure logs delivery.


Tool is parametrized with the total number of number that should be generated and the duration of
the generation process. For example, if you want to create a throughput of 100 lines per second
for a minute, you set total number of lines to 6000 and duration to 1 minute.

Parameters are passed through environment variables. There are no defaults, you should always
set up container parameters. Total number of line is parametrized through env variable
`LOGS_GENERATOR_LINES_TOTAL` and duration in go format is parametrized through env variable
`LOGS_GENERATOR_DURATION`.

Inside the container all log lines are written to the stdout.

Each line is on average 100 bytes long and follows this pattern:

```
2000-12-31T12:59:59Z <id> <method> /api/v1/namespaces/<namespace>/endpoints/<random_string> <random_number>
```

Where `<id>` refers to the number from 0 to `total_lines - 1`, which is unique for each
line in a given run of the container.

Examples:

```console
docker run -i \
  -e "LOGS_GENERATOR_LINES_TOTAL=10" \
  -e "LOGS_GENERATOR_DURATION=1s" \
  gcr.io/kubernetes-e2e-test-images/agnhost:1.1 \
  logs-generator
```

```console
kubectl run logs-generator \
  --generator=run-pod/v1 \
  --image=gcr.io/kubernetes-e2e-test-images/agnhost:1.1 \
  --restart=Never \
  --env "LOGS_GENERATOR_LINES_TOTAL=1000" \
  --env "LOGS_GENERATOR_DURATION=1m" \
  -- logs-generator
```

[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/test/images/logs-generator/README.md?pixel)]()

### net

The goal of this Go project is to consolidate all low-level
network testing "daemons" into one place. In network testing we
frequently have need of simple daemons (common/Runner) that perform
some "trivial" set of actions on a socket.

Usage:

* A package for each general area that is being tested, for example
  `nat/` will contain Runners that test various NAT features.
* Every runner should be registered via `main.go:makeRunnerMap()`.
* Runners receive a JSON options structure as to their configuration. `Run()`
  should return the disposition of the test.

Runners can be executed into two different ways, either through the
command-line or via an HTTP request:

Command-line:

```console
    kubectl exec test-agnhost -- /agnhost net -runner <runner> -options <json>
    kubectl exec test-agnhost -- /agnhost net \
        -runner nat-closewait-client \
        -options '{"RemoteAddr":"127.0.0.1:9999"}'
```

HTTP server:

```console
    kubectl exec test-agnhost -- /agnhost net --serve :8889
    kubectl exec test-agnhost -- curl -v -X POST localhost:8889/run/nat-closewait-server \
        -d '{"LocalAddr":"127.0.0.1:9999"}'
```

[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/test/images/net/README.md?pixel)]()

### netexec

TBA

Usage:

```console
    kubectl exec test-agnhost -- /agnhost netexec
```

### nettest

TBA

Usage:

```console
    kubectl exec test-agnhost -- /agnhost nettest
```

### no-snat-test-proxy

TBA

Usage:

```console
    kubectl exec test-agnhost -- /agnhost no-snat-test-proxy
```

### no-snat-test

TBA

Usage:

```console
    kubectl exec test-agnhost -- /agnhost no-snat-test
```

### pause

It will pause the execution of the binary. This can be used for containers
which have to be kept in a `Running` state for various purposes, including
executing other `agnhost` commands.

Usage:

```console
    kubectl exec test-agnhost -- /agnhost pause
```

### port-forward-tester

TBA

Usage:

```console
    kubectl exec test-agnhost -- /agnhost port-forward-tester
```

### serve-hostname

This subcommand is a small util app to serve your hostname on TCP and/or UDP. Useful for testing.

Usage:

```console
    kubectl exec test-agnhost -- /agnhost serve-hostname
```

[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/contrib/for-demos/serve_hostname/README.md?pixel)]()


[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/test/images/serve_hostname/README.md?pixel)]()

### webhook (Kubernetes External Admission Webhook)

The subcommand tests MutatingAdmissionWebhook and ValidatingAdmissionWebhook. After deploying
it to kubernetes cluster, administrator needs to create a ValidatingWebhookConfiguration
in kubernetes cluster to register remote webhook admission controllers.

TODO: add the reference when the document for admission webhook v1beta1 API is done.

Usage:

```console
    kubectl exec test-agnhost -- /agnhost webhook
```

## Image

The image can be found at `gcr.io/kubernetes-e2e-test-images/agnhost:1.0` for Linux
containers, and `e2eteam/agnhost:1.0` for Windows containers. In the future, the same
repository can be used for both OSes.
