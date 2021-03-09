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
# FLAGS=""

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

FLAGS="${FLAGS} --HACK-rename-next-to-compiler"
# new compiler, reset cache
if [ ! -d build/src ]
then
    cp -R src build/src
fi
I=1
# can remove once we have compiler hash
# see https://stackoverflow.com/questions/3601515/how-to-check-if-a-variable-is-set-in-bash
if [ -z "${FAST+x}" ]; then rm -rf .obj; fi
build/cx $FLAGS -Pcompiler:build/src -Pnext:src src/main.cx -o build/cx_test$I
SUM=$(checksum build/cx_test$I)
SUMNEXT=""
while true
do
    K=$((I+1))
    # can remove once we have compiler hash
    if [ -z "${FAST+x}" ]; then rm -rf .obj; fi
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
