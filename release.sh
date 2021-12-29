#!/usr/bin/env bash
set -euxo pipefail
if [ -e release ]
then
    echo "Release folder already exists!" 1>&2
    exit 1
fi
TARGET=release/neat
mkdir -p $TARGET
rm -rf .obj
./bootstrap.sh
build/neat -backend=c -Pcompiler:src -dump-intermediates build/intermediates.txt src/main.nt -c
mkdir $TARGET/intermediate
cp -R src/ $TARGET
cp $(cat build/intermediates.txt) $TARGET/intermediate/
cat > $TARGET/build.sh <<EOT
#!/usr/bin/env bash
CFLAGS="\${CFLAGS} -Ofast -fno-strict-aliasing -pthread"
gcc -fpic -rdynamic intermediate/* src/runtime.c -o neat -ldl \$CFLAGS
EOT
chmod +x $TARGET/build.sh
cat > $TARGET/neat.ini <<EOT
-syspackage compiler:src
-package root:.:compiler
-backend=c
-macro-backend=c
EOT
(cd $TARGET; ./build.sh)
NEAT=$TARGET/neat ./runtests.sh
rm $TARGET/neat
(cd release; zip -r ../release.zip neat)
