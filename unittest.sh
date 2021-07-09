#!/usr/bin/env bash
set -euxo pipefail
PACKAGES="-Pbuild:build:src -Psrc:src:compiler"
FLAGS="-lm -lpthread"
mkdir -p build
(
    echo "module unittest;"
    find src/std/ -name \*.nt |sed -e 's,/,.,g' -e 's/^src.\(.*\).nt$/import \1;/'
) > build/unittest.nt
neat -unittest -no-main $PACKAGES $FLAGS build/unittest.nt -o build/unittest
build/unittest
