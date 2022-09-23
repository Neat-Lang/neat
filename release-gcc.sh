#!/usr/bin/env bash
set -euxo pipefail
if [ $# -lt 1 ]
then
    echo "Usage: release-gcc.sh <version>"
    exit 1
fi
VERSION="$1"

LLVM=0
NTFLAGS="-O"
RELEASE=""
ARCH=64
ARCHFLAGS=""

if [ $(basename $0) == "release-llvm.sh" ]
then
    LLVM=1
    NTFLAGS="${NTFLAGS} -version=LLVMBackend"
    RELEASE="neat-$VERSION-llvm"
elif [ $(basename $0) == "release-gcc.sh" ]
then
    RELEASE="neat-$VERSION-gcc"
elif [ $(basename $0) == "release-gcc-32.sh" ]
then
    # TODO figure out why -O is broken
    NTFLAGS=""
    RELEASE="neat-$VERSION-gcc-32"
    ARCH=32
    ARCHFLAGS="-m32"
else
    echo "Unknown release name $(basename $0)"
    exit 1
fi

if [ -e "$RELEASE" ]
then
    echo "Release folder already exists!" 1>&2
    exit 1
fi

TARGET="$RELEASE"/"$RELEASE"
mkdir -p $TARGET

rm -rf .obj
./build.sh

build/neat -backend=c -Pcompiler:src -dump-intermediates build/intermediates.txt src/main.nt -c \
    $ARCHFLAGS $NTFLAGS

mkdir $TARGET/intermediate
cp --parents $(find src -xtype f -name '*.nt' -o -name runtime.c) $TARGET
cp $(cat build/intermediates.txt) $TARGET/intermediate/

if [ $LLVM -eq 0 ]
then
    cat > $TARGET/build.sh <<EOT
#!/usr/bin/env bash
set -exo pipefail
CFLAGS="\${CFLAGS} -Ofast -fno-strict-aliasing -pthread"
I=0
JOBS=16
OBJECTS=()
# poor man's make -j
for file in intermediate/*.c src/runtime.c; do
    obj=\${file%.c}.o
    gcc $ARCHFLAGS -c -fpic -rdynamic \$file -o \$obj &
    OBJECTS+=(\$obj)
    if [ \$I -ge \$JOBS ]; then wait -n; fi
    I=\$((I+1))
done
for i in \$(seq \$JOBS); do wait -n; done
gcc -fpic -rdynamic \${OBJECTS[@]} -o neat_bootstrap -ldl -lm $ARCHFLAGS \$CFLAGS
rm \${OBJECTS[@]}
./neat_bootstrap src/main.nt $NTFLAGS -o neat
rm neat_bootstrap
EOT
    cat > $TARGET/neat.ini <<EOT
-syspackage compiler:src
-backend=c
-macro-backend=c
-running-compiler-version=$VERSION
EOT
    if [ $ARCH == "32" ]
    then
        cat >> $TARGET/neat.ini <<EOT
-m32
-macro-m32
EOT
    fi
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
I=0
JOBS=16
OBJECTS=()
# poor man's make -j
for file in intermediate/*.c src/runtime.c; do
    obj=\${file%.c}.o
    gcc -c -fpic -rdynamic \$file -o \$obj &
    OBJECTS+=(\$obj)
    if [ \$I -ge \$JOBS ]; then wait -n; fi
    I=\$((I+1))
done
for i in \$(seq \$JOBS); do wait -n; done
gcc -fpic -rdynamic \${OBJECTS[@]} -o neat_bootstrap -ldl -lm -lLLVM \$CFLAGS
rm \${OBJECTS[@]}
./neat_bootstrap -macro-backend=c src/main.nt \${LLVM_NTFLAGS} $NTFLAGS -o neat
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
(cd "$RELEASE"
    zip -r ../"$RELEASE".zip "$RELEASE"
    tar caf ../"$RELEASE".tar.xz "$RELEASE")
