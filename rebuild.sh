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
# FLAGS="-O"
FLAGS=""
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
SUM="$(objdump -S build/cx_test$I |grep -v file\ format |md5sum)"
SUMNEXT=""
while true
do
    K=$((I+1))
    # can remove once we have compiler hash
    if [ -z "${FAST+x}" ]; then rm -rf .obj; fi
    build/cx_test$I $FLAGS -Pcompiler:src src/main.cx -o build/cx_test$K
    SUMNEXT="$(objdump -S build/cx_test$K |grep -v file\ format |md5sum)"
    if [ "$SUM" == "$SUMNEXT" ]; then break; fi
    SUM="$SUMNEXT"
    I=$K
done
mv build/cx_test$I build/cx
rm build/cx_test*
# store compiler source next to compiler
rm -rf build/src
cp -R src build/
