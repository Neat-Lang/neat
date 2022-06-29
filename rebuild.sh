#!/usr/bin/env bash
# kdevelop build mode
if [ ! -z "${BUILD+x}" ]
then
    FAST=1
    # no log spam
    set -euo pipefail
else
    set -euxo pipefail
fi
FLAGS="-O"
#FLAGS=""

if [ \! -z ${FAST+x} ]
then
    FLAGS="-j8"
fi

LLVM_CONFIG="/usr/lib/llvm/12/bin/llvm-config"
FLAGS="${FLAGS} -I$($LLVM_CONFIG --includedir) -L-L$($LLVM_CONFIG --libdir) \
    -version=LLVMBackend -macro-version=LLVMBackend"

function checksum {
    # approximate hash: outright remove all 16-byte constants
    # I couldn't find another way to handle compiler_hash_{add,mult}
    # remove the detritus at the start of the assembly line
    REMOVE_BYTES='s/^ *[0-9a-f]*:\t\([0-9a-f]\{2\} \)* *\t\?//'
    objdump -S $1 2>/dev/null |grep -v file\ format |\
        sed -e "$REMOVE_BYTES" |\
        sed -e 's/[0-9a-f]\{16\}//' |\
        md5sum
}

if [ ! -d build/src ]
then
    cp -R src build/src
fi

# include new runtime.c immediately
cp src/runtime.c build/src/
rm build/neat.ini || true

# turn off pass version flags on the next pass to avoid re-running into them
# use this opportunity to remove them
PASSFLAGS="-version='firstpass' -macro-version='firstpassmacro'"
if grep -qR 'firstpass' build/src; then PASSFLAGS=""; fi

I=1
NEXT=compiler$(($(build/neat -print-generation) + 1))
build/neat $FLAGS -next-generation ${PASSFLAGS} \
    -P$NEXT:src -Pcompiler:build/src src/main.nt -o build/neat_test$I

if [ \! -z ${FAST+x} ]
then
    mv build/neat_test$I build/neat
    # store compiler source next to compiler
    rm -rf build/src
    cp -R src build/
    cp neat.ini build
    exit
fi

cp neat.ini build/

SUM=$(checksum build/neat_test$I)
SUMNEXT=""
while true
do
    K=$((I+1))
    build/neat_test$I $FLAGS -Pcompiler:src src/main.nt -o build/neat_test$K
    SUMNEXT=$(checksum build/neat_test$K)
    if [ "$SUM" == "$SUMNEXT" ]; then break; fi
    SUM="$SUMNEXT"
    if [ "${K+x}" == "${STAGE+x}" ]
    then
        echo "Stage $STAGE reached, aborting"
        exit 1
    fi
    I=$K
done
mv build/neat_test$I build/neat
rm build/neat_test*
# store compiler source next to compiler
rm -rf build/src
cp -R src build/
