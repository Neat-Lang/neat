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
OPTFLAG="-O -release"
#OPTFLAG=""

JFLAG=""
if [ \! -z ${FAST+x} ]
then
    OPTFLAG=""
    JFLAG="-j8"
fi

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

FLAGS="$JFLAG -I$($LLVM_CONFIG --includedir) -L-L$($LLVM_CONFIG --libdir)"

TAG=v0.5.2
NEAT=.cache/bootstrap/"$TAG"/neat-"$TAG"-gcc/neat

if [ ! -f "$NEAT" ]
then
    echo "Downloading bootstrap compiler $TAG..."
    TARGET=.cache/bootstrap/"$TAG"
    rm -rf "$TARGET"
    mkdir -p "$TARGET"
    pushd "$TARGET"
    FILE=neat-"$TAG"-gcc.zip
    curl -L https://github.com/Neat-Lang/neat/releases/download/"$TAG"/"$FILE" --output "$FILE"
    unzip "$FILE"
    cd neat-"$TAG"-gcc
    echo "Building bootstrap compiler $TAG..."
    ./build.sh
    popd
fi

mkdir -p build

echo "Building stage 1..."
# FIXME remove hack
cp src/runtime.c .cache/bootstrap/v0.5.2/neat-v0.5.2-gcc/src/runtime.c
FLAGS="$FLAGS -version=LLVMBackend"
FLAGS="$FLAGS -file-id-output build/fileIdPins"
# see generation.md
NEXT=compiler$(($($NEAT -print-generation) + 1))
$NEAT $FLAGS -backend=c -macro-backend=c -next-generation -P$NEXT:src -j src/main.nt \
    -version=firstpass2 -o build/neat_stage1
cat build/fileIdPins -<<EOF > build/neat.ini
-syspackage compiler:src
-running-compiler-version=$TAG
EOF
rm build/fileIdPins
NEAT=build/neat_stage1

# store compiler source next to compiler
rm -rf build/src
cp -R src build/

echo "Building stage 2..."
FLAGS="$FLAGS -version=LLVMBackend"
# see generation.md
$NEAT $FLAGS -backend=llvm -macro-backend=c -macro-version=oldabi -Pcompiler:src -j src/main.nt \
    -o build/neat_stage2
NEAT=build/neat_stage2

echo "Building stage 3..."
$NEAT $FLAGS $OPTFLAG -backend=llvm -macro-backend=llvm -Pcompiler:src -j src/main.nt \
    -o build/neat_stage3
NEAT=build/neat_stage3

cp -f $NEAT build/neat
rm build/neat_stage*

cat build/fileIdPins -<<EOF > build/neat.ini
-syspackage compiler:src
-running-compiler-version=$TAG
EOF
rm build/fileIdPins
