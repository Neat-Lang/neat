#!/usr/bin/env bash
if [ -v LLVM_CONFIG ]
then
    :
elif [ -f "/usr/lib/llvm-15/bin/llvm-config" ]
then
    LLVM_CONFIG="/usr/lib/llvm-15/bin/llvm-config"
elif [ -f "/usr/lib/llvm/15/bin/llvm-config" ]
then
    LLVM_CONFIG="/usr/lib/llvm/15/bin/llvm-config"
elif [ -f "/usr/lib/llvm15/bin/llvm-config" ]
then
    LLVM_CONFIG="/usr/lib/llvm15/bin/llvm-config"
else
    echo "Cannot find llvm-15 llvm-config!"
    exit 1
fi
