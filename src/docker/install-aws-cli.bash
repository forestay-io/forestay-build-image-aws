#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Forestay contributors (Fred Cooke)
#
# AWS CLI v2, for accessanalyzer validate-policy.
#
# Binary from Amazon, checksum from the index, so a compromise of either one
# alone is caught.
#
# Reads AWS_CLI_VERSION, AWS_CLI_INDEX and DOCKER_PLATFORM_CPU_ARCHITECTURE
# from the image environment.

set -euo pipefail

# Amazon spells the architecture x86_64/aarch64, the index spells it amd/arm
case "${DOCKER_PLATFORM_CPU_ARCHITECTURE}" in
  amd64) aws_arch=x86_64; idx_arch=amd ;;
  arm64) aws_arch=aarch64; idx_arch=arm ;;
  *) echo "unsupported architecture ${DOCKER_PLATFORM_CPU_ARCHITECTURE}" >&2; exit 1 ;;
esac

cd /tmp

curl -fsSL -o awscliv2.zip \
  "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}-${AWS_CLI_VERSION}.zip"
curl -fsSL -o trusted.sha512 \
  "${AWS_CLI_INDEX}/${AWS_CLI_VERSION}/${idx_arch}-${AWS_CLI_VERSION}.sha512"

echo "$(cat trusted.sha512)  awscliv2.zip" | sha512sum --check

unzip -q awscliv2.zip
./aws/install

rm -rf awscliv2.zip trusted.sha512 aws
