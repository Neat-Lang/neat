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
ARCHS=64

if [ $(basename $0) == "release-llvm.sh" ]
then
    LLVM=1
    NTFLAGS="${NTFLAGS} -version=LLVMBackend"
    RELEASE="neat-$VERSION-llvm"
elif [ $(basename $0) == "release-gcc.sh" ]
then
    ARCHS="32 64"
    RELEASE="neat-$VERSION-gcc"
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

cp --parents $(find src -xtype f -name '*.nt' -o -name runtime.c) $TARGET

for ARCH in $ARCHS
do
    ARCHFLAGS=""
    if [ ARCH == "32" ]
    then
        ARCHFLAGS = "-m32"
    fi
    build/neat -backend=c -Pcompiler:src -dump-intermediates build/intermediates.txt src/main.nt -c \
        $ARCHFLAGS $NTFLAGS

    mkdir $TARGET/intermediate_$ARCH
    cp $(cat build/intermediates.txt) $TARGET/intermediate_$ARCH/
done

if [ $LLVM -eq 0 ]
then
    cat > $TARGET/build.sh <<EOT
#!/usr/bin/env bash
set -exo pipefail
if [ "\${ARCH}" == "" ]
then
    ARCH=\$(getconf LONG_BIT)
    echo "ARCH not set, guessing \$ARCH"
fi
DEFAULT_ARCH=""
echo "int main(void) {}" |gcc -x c - -o _platform_test
if (file _platform_test |grep -q 32-bit)
then
    DEFAULT_ARCH="32"
elif (file _platform_test |grep -q 64-bit)
then
    DEFAULT_ARCH="64"
else
    echo "Cannot determine architecture!"
    exit 1
fi
rm _platform_test
ARCHFLAG=""
if [ "\${ARCH}" != "\${DEFAULT_ARCH}" ]
then
    # force targetting the ARCH architecture
    ARCHFLAG="-m\${ARCH}"
fi
CFLAGS="\${CFLAGS} -Ofast -fno-strict-aliasing -pthread"
I=0
JOBS=16
OBJECTS=()
# poor man's make -j
for file in intermediate_\${ARCH}/*.c src/runtime.c; do
    obj=\${file%.c}.o
    gcc \$ARCHFLAG -c -fpic -rdynamic \$file -o \$obj &
    OBJECTS+=(\$obj)
    if [ \$I -ge \$JOBS ]; then wait -n; fi
    I=\$((I+1))
done
for i in \$(seq \$JOBS); do wait -n; done
gcc -fpic -rdynamic \${OBJECTS[@]} -o neat_bootstrap -ldl -lm \$ARCHFLAG \$CFLAGS
rm \${OBJECTS[@]}
cat > neat.ini <<EOI
-syspackage compiler:src
-backend=c
-macro-backend=c
-running-compiler-version=$VERSION
-extra-cflags=\$ARCHFLAG
EOI
if [ \${ARCH} == "32" ]
then
    cat >> neat.ini <<EOI
-m32
-macro-m32
EOI
fi
./neat_bootstrap src/main.nt $NTFLAGS -o neat
rm neat_bootstrap
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

for ARCH in $ARCHS
do
    echo "Test $ARCH"
    TEST_TARGET="test_${RELEASE}_${ARCH}"
    cp -R "${TARGET}" "${TEST_TARGET}"
    (cd "${TEST_TARGET}" && ./build.sh)
    NEAT="${TEST_TARGET}"/neat ./runtests.sh
    rm -rf "${TEST_TARGET}"
done
(cd "$RELEASE"
    zip -r ../"$RELEASE".zip "$RELEASE"
    tar caf ../"$RELEASE".tar.xz "$RELEASE")
