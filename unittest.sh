#!/usr/bin/env bash
set -euxo pipefail
PACKAGES="-Pbuild:build:src -Psrc:src:compiler"
FLAGS="-lm -lpthread -j8"
RUN="build/unittest"

if [ "${1:-}" = "win64" ]; then
    FLAGS="${FLAGS} --target x86_64-w64-mingw32"
    RUN="wine build/unittest.exe"
    function filter() {
        grep -v ' neat' |grep -v ' backend' |grep -v 'main' | grep -v 'std.macro' |\
            grep -v 'std.time' | # TODO \
            grep -v 'std.socket' | # TODO \
            grep -v 'std.process' # TODO
    }
    shift
else
    . ./find-llvm-config.sh
    FLAGS="${FLAGS} -I$($LLVM_CONFIG --includedir) -L-L$($LLVM_CONFIG --libdir) -version=LLVMBackend"
    function filter() {
        cat
    }
fi

mkdir -p build
(
    echo "module unittest;"
    find src/ -name \*.nt |sed -e 's,/,.,g' -e 's/^src.\(.*\).nt$/import \1;/' |filter
) > build/unittest.nt


neat --unittest=src --no-main $PACKAGES $FLAGS build/unittest.nt -o build/unittest
eval "${RUN}"
