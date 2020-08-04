#!/bin/bash
set -euxo pipefail
make build/stage1
build/stage1 -Isrc/stage2 main.cx -- -Isrc/stage2 main.cx -o build/stage2
