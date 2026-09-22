# Forestay Build Image AWS

Toolchain image in which each Forestay AWS Go build, test, code generation and
policy validation runs, locally and in CI.


## Purposes

The image carries everything the build needs, so nothing is fetched from
outside the org while building or testing: tools, envtest binaries, all Go
module dependencies of the consuming repo, and a prebuilt standard library. The
final environment locks that in:

```
GOPROXY=off
GOTOOLCHAIN=local
GOFLAGS=-mod=readonly
```

If the consuming build tries to use the network, it fails immediately, instead
of quietly succeeding on a box that happens to have access.


## Contents

| Item                   | Pin source                        | Purpose                                                    |
|------------------------|-----------------------------------|------------------------------------------------------------|
| Go                     | FROM statement version and digest | Compiler and toolchain                                     |
| `controller-gen`       | `CONTROLLER_GEN_VERSION`          | CRD and deepcopy generation                                |
| `staticcheck`          | `STATICCHECK_VERSION`             | Static analysis                                            |
| `golangci-lint`        | `GOLANGCI_LINT_VERSION`           | depguard, keeping `pkg/` provider neutral                  |
| `setup-envtest`        | `SETUP_ENVTEST_VERSION`           | envtest tooling                                            |
| envtest control planes | `ENVTEST_VERSIONS`                | `kube-apiserver` and `etcd` per supported Kubernetes minor |
| AWS CLI v2             | `AWS_CLI_VERSION`                 | `accessanalyzer validate-policy`                           |

Each pin, other than the FROM image, is an `ENV` in `src/docker/Dockerfile`,
which is also what the tests read. Go tools install through the module proxy,
so `go.sum` verification covers them and no separate checksum table is needed.
AWS publishes no checksums for the CLI binaries, so we fetch independent
trusted ones from [kube-kaptain/aws-cli-v2-index](https://github.com/kube-kaptain/aws-cli-v2-index),
using the method that project documents on its releases: binary from Amazon,
checksum from the index, `sha512sum --check` across the two. A compromise of
either source alone is caught, and bumping the CLI is a one line change because
no checksums are stored in the Dockerfile. envtest tarballs are verified
against the `.sha512` published beside each release.

envtest control planes land in `${ENVTEST_ROOT}/<version>/`. Point
`KUBEBUILDER_ASSETS` at the directory for the minor under test. Nothing
downloads at test time.


## Changing a Go dependency

A deliberate three step process:

1. In the consuming repo adjust the `go.mod` dependencies as needed for your
   change, then run `src/bin/resolve-deps.bash` to generate or update `go.sum`.
   Or name the modules as arguments instead:
   `src/bin/resolve-deps.bash <module>@<version> [more…]` does both at once.
   Either way the script tidies, downloads, and refuses anything unpinned or
   simply too new to be trusted.
2. In this repo root, run `src/bin/refresh-deps.bash`, which takes no
   arguments. Review the diff, commit, PR, and merge to release.
3. In the consuming repo, bump `BuildImageVersion` and commit that and `go.mod`
   and `go.sum` together.

Without this process the build is slower and less secure. This structure allows
for better security since the image allows no go updates therefore requiring a
dependency change to be a planned change, not adhoc and risky. The build proves
that the pair are in sync: with `GOPROXY=off`, any module not baked into the
image fails the consuming build immediately.


## Build

With Kaptain setup locally use `kaptain build` to build the project. It's set
up to build `linux/amd64` and `linux/arm64` from the one Dockerfile in
`src/docker/`, once per architecture into separate build contexts, and then
publish the multi-architecture manifest.

`.github/bin/run-tests.bash` runs as the `postDockerTests` hook. It asserts
that all tools run and report the version they were pinned to, that an envtest
control plane exists for every listed Kubernetes minor, that the baked
dependencies are pinned and old enough, and that the network lock is applied.

The dependency check runs `src/bin/check-dep-age.bash` inside the built image,
mounted from this repo rather than baked in, because an image that supplied
the script judging it could ship one that passes.


## Licence

See [LICENSE.md](LICENSE.md).
