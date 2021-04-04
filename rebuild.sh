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
    FLAGS=""
fi

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

# new compiler, reset cache
if [ ! -d build/src ]
then
    cp -R src build/src
fi
I=1
NEXT=compiler$(($(build/cx -print-generation) + 1))
build/cx $FLAGS -next-generation -P$NEXT:src -Pcompiler:build/src src/main.cx -o build/cx_test$I

if [ \! -z ${FAST+x} ]
then
    mv build/cx_test$I build/cx
    exit
fi

cp cx.ini build/

SUM=$(checksum build/cx_test$I)
SUMNEXT=""
while true
do
    K=$((I+1))
    build/cx_test$I $FLAGS -Pcompiler:src src/main.cx -o build/cx_test$K
    SUMNEXT=$(checksum build/cx_test$K)
    if [ "$SUM" == "$SUMNEXT" ]; then break; fi
    SUM="$SUMNEXT"
    if [ "${K+x}" == "${STAGE+x}" ]
    then
        echo "Stage $STAGE reached, aborting"
        exit 1
    fi
    I=$K
done
mv build/cx_test$I build/cx
rm build/cx_test*
# store compiler source next to compiler
rm -rf build/src
cp -R src build/
