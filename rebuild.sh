#!/usr/bin/env bash
set -euxo pipefail
FLAGS="-O"
# FLAGS=""
if [ ! -d build/src ]
then
    cp -R src build/src
fi
I=1
build/cx $FLAGS -Pcompiler:build/src -Pnext:src src/main.cx -o build/cx_test$I
SUM="$(objdump -S build/cx_test$I |grep -v file\ format |md5sum)"
SUMNEXT=""
while true
do
    K=$((I+1))
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
