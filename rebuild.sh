#!/bin/bash
set -euxo pipefail
I=1
build/cx -O -Isrc src/main.cx -o build/cx_test$I
SUM="$(objdump -S build/cx_test$I |grep -v file\ format |md5sum)"
SUMNEXT=""
while true
do
    K=$((I+1))
    build/cx_test$I -O -Isrc -Psrc:src src/main.cx -o build/cx_test$K
    SUMNEXT="$(objdump -S build/cx_test$K |grep -v file\ format |md5sum)"
    if [ "$SUM" == "$SUMNEXT" ]; then break; fi
    SUM="$SUMNEXT"
    I=$K
done
mv build/cx_test$I build/cx
rm build/cx_test*
