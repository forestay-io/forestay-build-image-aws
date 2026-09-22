# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Forestay contributors (Fred Cooke)
#
# Toolchain image for the Forestay AWS variant: builds, tests, code
# generation and policy validation. One of only two places in the project
# referencing an image from outside the org.
#
FROM docker.io/library/golang:1.27.1-bookworm@sha256:648f440f42a0958804efb24df176f806f9d353b41f1c0627f666428e40310f6b

# Supplied by the build system
ARG VERSION
ARG PROJECT_NAME
ARG DOCKER_TAG
ARG DOCKER_IMAGE_NAME
ARG DOCKER_PLATFORM_CPU_ARCHITECTURE
# ^ "amd64" or "arm64"

# Leave a trail of breadcrumbs
LABEL description="Forestay - build and test toolchain image"
LABEL base.project.name="${PROJECT_NAME}"
LABEL base.version="${VERSION}"
LABEL base.docker.tag="${DOCKER_TAG}"
LABEL base.docker.image.name="${DOCKER_IMAGE_NAME}"

# Deterministic time and text handling for all processes
ENV TZ=UTC
ENV LC_ALL=C

# Dependency versions
ENV CONTROLLER_GEN_VERSION=v0.22.0
ENV STATICCHECK_VERSION=2026.2.1
ENV GOLANGCI_LINT_VERSION=v2.13.2
ENV SETUP_ENVTEST_VERSION=v0.25.1
ENV AWS_CLI_VERSION=2.36.49

# AWS publishes no checksum, so trust comes from an independent second source
ENV AWS_CLI_INDEX=https://github.com/kube-kaptain/aws-cli-v2-index/releases/download

# Add the 3 scripts needed to prep the image
COPY install-aws-cli.bash /usr/local/bin/
COPY install-envtest.bash /usr/local/bin/
COPY populate-go-cache.bash /usr/local/bin/

# Pull in the declaration of our dependencies
COPY go.mod go.sum /opt/deps/

# Install unzip for the AWS CLI archives
RUN apt-get update
RUN apt-get install --no-install-recommends -y unzip
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

# Install go build tooling
RUN go install "sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION}"
RUN go install "honnef.co/go/tools/cmd/staticcheck@${STATICCHECK_VERSION}"
RUN go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"
RUN go install "sigs.k8s.io/controller-runtime/tools/setup-envtest@${SETUP_ENVTEST_VERSION}"

# Install AWS CLI v2, securely
RUN install-aws-cli.bash

# Install envtest control planes for the floor and ceiling of the supported
# range. CEL features only get added, so a rule too new fails at the floor and
# one since removed fails at the ceiling. See the Compatibility.md doc in the
# main forestay repo.
ENV ENVTEST_VERSIONS="1.29.5 1.37.0"
ENV ENVTEST_ROOT=/opt/envtest
RUN install-envtest.bash

# Compile the stdlib and dependencies into GOCACHE for both architectures.
# Flags must match build-binaries.bash in the consumer repo or the entries are
# keyed differently and never hit.
RUN populate-go-cache.bash

# Never override these downstream, use the process in the README instead
ENV GOPROXY=off
ENV GOTOOLCHAIN=local
ENV GOFLAGS=-mod=readonly

WORKDIR /workspace
