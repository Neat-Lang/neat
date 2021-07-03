#!/usr/bin/env bash
set -euxo pipefail
PACKAGES="-Pbuild:build:src -Psrc:src:compiler"
FLAGS="-lm -lpthread"
mkdir -p build
(
    echo "module unittest;"
    find src/std/ -name \*.cx |sed -e 's,/,.,g' -e 's/^src.\(.*\).cx$/import \1;/'
) > build/unittest.cx
cx -unittest -no-main $PACKAGES $FLAGS build/unittest.cx -o build/unittest
build/unittest
