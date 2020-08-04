#!/bin/bash
set -euxo pipefail
build/stage2 -Isrc/stage2 main.cx -o build/stage2_test
build/stage2_test -Isrc/stage2 main.cx -o build/stage2
