#!/bin/sh
set -eu

# Since the language is self-hosting, we require a copy of the compiler in order to
# produce another copy. To sidestep this circular requirement, we check out a sequence
# of historic git revisions that did have a working bootstrap compiler, and use them to
# bootstrap up to the present.
# Note that you need a copy of LDC around 2.089.1-ish in the path.
function at_revision {
    rev=$1
    build=$2
    output=$3

    rm -rf build/$rev
    mkdir -p build/$rev
    cd build/$rev
    git clone -s ../.. .
    git checkout -q $rev
    git submodule -q update --init
    $build
    cd ../..
    cp build/$rev/$output build/cx
    rm -rf build/$rev
    echo "=== build/cx from $rev ==="
    echo
}
function dbootstrap {
    make build/stage1
    echo "- stage1/stage2/stage2"
    build/stage1 -Isrc/stage2 main.cx -- -Isrc/stage2 src/stage2/main.cx -o build/stage2
}
function rebuild {
    mkdir build
    cp ../../build/cx build/$1
    ./rebuild.sh
}
# before structs in the compiler
at_revision 'f65eb856f00b3016025b105c4475b1b9c623bdf3' 'dbootstrap' 'build/stage2'
# move runtime.c to src/
at_revision 'fd26349126358e19671f5e11f4a67e615e454b5f' 'rebuild stage2' 'build/stage2'
# idk, something about floats
at_revision 'edde8f615d72034d7fe645226c43156238895c09' 'rebuild cx' 'build/cx'
# float literals
at_revision 'e88bcc52f621c7e47f3a667554d7401c5d72be2e' 'rebuild cx' 'build/cx'
# package includes
at_revision 'f6078a3470f7826b566b7eed70acd91f3c647960' 'rebuild cx' 'build/cx'
./rebuild.sh
echo "=== build/cx from master ==="
