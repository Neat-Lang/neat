#!/bin/bash
set -euxo pipefail
I=1
build/stage2 -Isrc/stage2 main.cx -o build/stage2_test$I
SUM="$(objdump -S build/stage2_test$I |grep -v file\ format |md5sum)"
SUMNEXT=""
while true
do
    K=$((I+1))
    build/stage2_test$I -Isrc/stage2 main.cx -o build/stage2_test$K
    SUMNEXT="$(objdump -S build/stage2_test$K |grep -v file\ format |md5sum)"
    if [ "$SUM" == "$SUMNEXT" ]; then break; fi
    SUM="$SUMNEXT"
    I=$K
done
mv build/stage2_test$I build/stage2
