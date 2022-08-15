#!/usr/bin/env bash
set -euxo pipefail
if [ $# -lt 1 ]
then
    echo "Usage: release-gcc.sh <version>"
    exit 1
fi
VERSION="$1"

LLVM=0
NTFLAGS=""
RELEASE="neat-$VERSION-gcc"

if [ $(basename $0) != "release-gcc.sh" ]
then
    LLVM=1
    NTFLAGS="${NTFLAGS} -version=LLVMBackend"
    RELEASE="neat-$VERSION-llvm"
fi

if [ -e "$RELEASE" ]
then
    echo "Release folder already exists!" 1>&2
    exit 1
fi

TARGET="$RELEASE"/neat
mkdir -p $TARGET

rm -rf .obj
./bootstrap.sh

build/neat -backend=c -Pcompiler:src -dump-intermediates build/intermediates.txt src/main.nt -c $NTFLAGS

mkdir $TARGET/intermediate
cp -R src/ $TARGET
cp $(cat build/intermediates.txt) $TARGET/intermediate/

if [ $LLVM -eq 0 ]
then
    cat > $TARGET/build.sh <<EOT
#!/usr/bin/env bash
set -exo pipefail
CFLAGS="\${CFLAGS} -Ofast -fno-strict-aliasing -pthread"
gcc -fpic -rdynamic intermediate/* src/runtime.c -o neat -ldl -lm \$CFLAGS
EOT
    cat > $TARGET/neat.ini <<EOT
-syspackage compiler:src
-backend=c
-macro-backend=c
-running-compiler-version=$VERSION
EOT
else
    if [ -f "/usr/lib/llvm/14/bin/llvm-config" ]
    then
        LLVM_CONFIG="/usr/lib/llvm/14/bin/llvm-config"
    elif [ -f "/usr/lib/llvm-14/bin/llvm-config" ]
    then
        LLVM_CONFIG="/usr/lib/llvm-14/bin/llvm-config"
    else
        echo "Cannot find llvm-config!" 1>&2
        exit 1
    fi
    CFLAGS="${CFLAGS:+ }-I$($LLVM_CONFIG --includedir) -L$($LLVM_CONFIG --libdir)"
    cat > $TARGET/build.sh <<EOT
#!/usr/bin/env bash
set -exo pipefail
if [ -f "/usr/lib/llvm/14/bin/llvm-config" ]
then
    LLVM_CONFIG="/usr/lib/llvm/14/bin/llvm-config"
elif [ -f "/usr/lib/llvm-14/bin/llvm-config" ]
then
    LLVM_CONFIG="/usr/lib/llvm-14/bin/llvm-config"
else
    echo "Cannot find llvm-config!" 1>&2
    exit 1
fi
LLVM_CFLAGS="-I\$(\$LLVM_CONFIG --includedir) -L\$(\$LLVM_CONFIG --libdir)"
LLVM_NTFLAGS="-I\$(\$LLVM_CONFIG --includedir) -L-L\$(\$LLVM_CONFIG --libdir)"
CFLAGS="\${CFLAGS:+ } \${LLVM_CFLAGS} -O2 -fno-strict-aliasing -pthread"
gcc -fpic -rdynamic intermediate/* src/runtime.c -o neat_bootstrap -ldl -lm -lLLVM \$CFLAGS
./neat_bootstrap -O -macro-backend=c src/main.nt \${LLVM_NTFLAGS} $NTFLAGS -o neat
rm neat_bootstrap
EOT
    cat > $TARGET/neat.ini <<EOT
-syspackage compiler:src
-backend=llvm
-macro-backend=llvm
-version=LLVMBackend
-macro-version=LLVMBackend
-running-compiler-version=$VERSION
EOT
fi
chmod +x $TARGET/build.sh

(cd $TARGET; ./build.sh)
NEAT=$TARGET/neat ./runtests.sh
rm $TARGET/neat
rm -rf $TARGET/.obj
(cd "$RELEASE"; zip -r ../"$RELEASE".zip neat)
