#!/bin/bash
set -euxo pipefail
build/stage2 -Isrc/stage2 main.cx -o build/stage2_test1
build/stage2_test1 -Isrc/stage2 main.cx -o build/stage2_test2
build/stage2_test2 -Isrc/stage2 main.cx -o build/stage2
