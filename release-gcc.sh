#!/usr/bin/env bash
set -euxo pipefail
if [ $# -lt 1 ]
then
    echo "Usage: release-gcc.sh <version>"
    exit 1
fi
VERSION="$1"

BUILD=""
STAGE1FLAGS="-O"
STAGE2FLAGS="-O"
RELEASE=""
ARCHS=64
export WINEDEBUG=-all

if [ $(basename $0) == "release-llvm.sh" ]
then
    BUILD="llvm"
    STAGE1FLAGS="${STAGE1FLAGS} -version=LLVMBackend"
    STAGE2FLAGS="${STAGE2FLAGS} -macro-version=LLVMBackend -version=LLVMBackend"
    RELEASE="neat-$VERSION-llvm"
elif [ $(basename $0) == "release-gcc.sh" ]
then
    BUILD="gcc"
    ARCHS="32 64"
    RELEASE="neat-$VERSION-gcc"
elif [ $(basename $0) == "release-win64-gcc.sh" ]
then
    BUILD="win64-gcc"
    RELEASE="neat-$VERSION-win64-gcc"
    STAGE1FLAGS="${STAGE1FLAGS} -target=windows -dllsafe"
    STAGE2FLAGS="${STAGE2FLAGS} -macro-target=windows -macro-dllsafe -target=windows -dllsafe"
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
        $ARCHFLAGS $STAGE1FLAGS

    mkdir $TARGET/intermediate_$ARCH
    cp $(tail -n +2 build/intermediates.txt) $TARGET/intermediate_$ARCH/
    head -1 build/intermediates.txt > $TARGET/main.txt
done

if [ "$BUILD" = "gcc" ]
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
DMAIN="-DMAIN=\$(cat main.txt)"
CFLAGS="\${CFLAGS} -Ofast -fno-strict-aliasing -pthread"
I=0
JOBS=16
OBJECTS=()
# poor man's make -j
for file in intermediate_\${ARCH}/*.c src/runtime.c; do
    obj=\${file%.c}.o
    gcc \$ARCHFLAG -c -fpic -rdynamic -fno-strict-aliasing \$DMAIN \$file -o \$obj &
    OBJECTS+=(\$obj)
    if [ \$I -ge \$JOBS ]; then wait -n; fi
    I=\$((I+1))
done
for i in \$(seq \$JOBS); do wait -n; done
gcc \$ARCHFLAG -fpic -rdynamic -fno-strict-aliasing \${OBJECTS[@]} -o neat_bootstrap -ldl -lm \$CFLAGS
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
./neat_bootstrap -j src/main.nt $STAGE2FLAGS -o neat
rm neat_bootstrap
EOT
    chmod +x $TARGET/build.sh
elif [ "$BUILD" = "win64-gcc" ]
then
    cat > $TARGET/build.bat <<EOT
SETLOCAL
FOR /F %%I IN (main.txt) DO SET "DMAIN=-DMAIN=%%I"
SET "CFLAGS=%CFLAGS% -Ofast -fno-strict-aliasing -pthread"
SET "LINKFLAGS=-Wl,/STACK:8388608"
FOR /R %%F IN (*.c) DO (
    SET "obj=%%~dpnF.o"
    SETLOCAL ENABLEDELAYEDEXPANSION
    ECHO gcc -m64 -w -c -g -fpic -rdynamic -fno-strict-aliasing %DMAIN% %%~fF -o !obj!
    gcc -m64 -w -c -g -fpic -rdynamic -fno-strict-aliasing %DMAIN% %%~fF -o !obj!
    CALL SET obj=%%obj:\\=@%%
    CALL SET obj=%%obj:@=\\\\%%
    ECHO !obj! >> objects.txt
    ENDLOCAL
)
gcc -m64 -g -fpic -rdynamic -fno-strict-aliasing @objects.txt -o neat_bootstrap -lm %CFLAGS% %LINKFLAGS%
REM FOR /F "delims=" %%I IN (objects.txt) DO DEL %%I
ECHO -syspackage compiler:src > neat.ini
ECHO -backend=c >> neat.ini
ECHO -target=x86_64-w64-mingw32 >> neat.ini
ECHO -macro-target=x86_64-w64-mingw32 >> neat.ini
ECHO -macro-dllsafe >> neat.ini
ECHO -running-compiler-version=$VERSION >> neat.ini
neat_bootstrap -j src/main.nt $STAGE2FLAGS -o neat
REM DEL neat_bootstrap
ENDLOCAL
EOT
elif [ "$BUILD" = "llvm" ]
then
    . ./find-llvm-config.sh
    CFLAGS="${CFLAGS:+ }-I$($LLVM_CONFIG --includedir) -L$($LLVM_CONFIG --libdir)"
    install -v ./find-llvm-config.sh "$TARGET"
    cat > $TARGET/build.sh <<EOT
#!/usr/bin/env bash
set -exo pipefail
. ./find-llvm-config.sh
LLVM_CFLAGS="-I\$(\$LLVM_CONFIG --includedir) -L\$(\$LLVM_CONFIG --libdir)"
LLVM_NTFLAGS="-I\$(\$LLVM_CONFIG --includedir) -L-L\$(\$LLVM_CONFIG --libdir)"
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
DMAIN="-DMAIN=\$(cat main.txt)"
CFLAGS="\${CFLAGS:+ } \${LLVM_CFLAGS} -O2 -fno-strict-aliasing -pthread"
I=0
JOBS=16
OBJECTS=()
# poor man's make -j
for file in intermediate_\${ARCH}/*.c src/runtime.c; do
    obj=\${file%.c}.o
    gcc \$ARCHFLAG -c -fpic -rdynamic -fno-strict-aliasing \$DMAIN \$file -o \$obj &
    OBJECTS+=(\$obj)
    if [ \$I -ge \$JOBS ]; then wait -n; fi
    I=\$((I+1))
done
for i in \$(seq \$JOBS); do wait -n; done
gcc \$ARCHFLAG -fpic -rdynamic -fno-strict-aliasing \${OBJECTS[@]} -o neat_bootstrap -ldl -lm -lLLVM \$CFLAGS
rm \${OBJECTS[@]}
./neat_bootstrap -j -macro-backend=c src/main.nt \${LLVM_NTFLAGS} $STAGE2FLAGS -o neat
rm neat_bootstrap
EOT
    chmod +x $TARGET/build.sh
    cat > $TARGET/neat.ini <<EOT
-syspackage compiler:src
-backend=llvm
-macro-backend=llvm
-version=LLVMBackend
-macro-version=LLVMBackend
-running-compiler-version=$VERSION
-extra-cflags=\$ARCHFLAG
EOT
else
    echo "Unknown build '$BUILD'!"
    exit 1
fi

for ARCH in $ARCHS
do
    echo "Test $ARCH"
    TEST_TARGET="test_${RELEASE}_${ARCH}"
    cp -R "${TARGET}" "${TEST_TARGET}"
    if [ "$BUILD" = "win64-gcc" ]; then
        (cd "${TEST_TARGET}" &&  wine build.bat)
    else
        (cd "${TEST_TARGET}" && ./build.sh)
    fi
    if [ "$BUILD" = "win64-gcc" ]; then
        NEAT="wine \"${TEST_TARGET}\"/neat.exe"
        ./runtests.sh win64
    else
        NEAT="${TEST_TARGET}"/neat
        ./runtests.sh
    fi
    rm -rf "${TEST_TARGET}"
done
(cd "$RELEASE"
    zip -r ../"$RELEASE".zip "$RELEASE"
    tar caf ../"$RELEASE".tar.xz "$RELEASE")
