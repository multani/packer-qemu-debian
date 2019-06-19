#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

set -x

IMAGE_PATH=$1

cd $(dirname $IMAGE_PATH)
sha256sum $(basename $IMAGE_PATH) > SHA256SUMS
