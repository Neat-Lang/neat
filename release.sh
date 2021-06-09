#!/usr/bin/env bash
set -euxo pipefail
if [ -e release ]
then
    echo "Release folder already exists!" 1>&2
    exit 1
fi
TARGET=release/cx
mkdir -p $TARGET
rm -rf .obj
./bootstrap.sh
build/cx -backend=c -Pcompiler:src -dump-intermediates build/intermediates.txt src/main.cx -c
mkdir $TARGET/intermediate
cp -R src/ $TARGET
cp $(cat build/intermediates.txt) $TARGET/intermediate/
cat > $TARGET/build.sh <<EOT
#!/usr/bin/env bash
gcc -fpic -rdynamic intermediate/* src/runtime.c -o cx -ldl
EOT
chmod +x $TARGET/build.sh
cat > $TARGET/cx.ini <<EOT
-syspackage compiler:src
-package root:.:compiler
-backend=c
-macro-backend=c
EOT
(cd $TARGET; ./build.sh)
CX=$TARGET/cx ./runtests.sh
rm $TARGET/cx
(cd release; zip -r ../release.zip cx)
