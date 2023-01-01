#!/usr/bin/env bash
set -euxo pipefail
PACKAGES="-Pbuild:build:src -Psrc:src:compiler"
FLAGS="-lm -lpthread"
mkdir -p build
(
    echo "module unittest;"
    find src/ -name \*.nt |sed -e 's,/,.,g' -e 's/^src.\(.*\).nt$/import \1;/'
) > build/unittest.nt

LLVM_CONFIG=${LLVM_CONFIG:-"/usr/bin/llvm-config-14"}
FLAGS="${FLAGS} -I$($LLVM_CONFIG --includedir) -L-L$($LLVM_CONFIG --libdir)"

neat -unittest -no-main $PACKAGES $FLAGS build/unittest.nt -o build/unittest
build/unittest
