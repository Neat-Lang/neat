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
    # bleeeh this should not be here, this is not generic, but meh
    if [ -d build/$rev/build/src ]; then
        rm -rf build/src
        cp -R build/$rev/build/src build/
    fi
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
    # also not generic, see above
    if [ -d ../../build/src ]; then
        cp -R ../../build/src build
    fi
    sed -i -e 's/-O//' rebuild.sh
    bash rebuild.sh
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
at_revision '8a9cdec868d643703ba6b2f8be73ffd9bc3e76fe' 'rebuild cx' 'build/cx'
# import package()
at_revision 'ba44e97c4dc8b721710cfaf023a711acc75c6cfd' 'rebuild cx' 'build/cx'
# idk but it crashes otherwise
at_revision '56ff9817e5e4de1aa9100f27a29565bb2a2272b8' 'rebuild cx' 'build/cx'
# mangling
at_revision 'e434a668cebd814cbac7a2bfcb6d53417a40a3db' 'rebuild cx' 'build/cx'
# case prep
at_revision '5df536b089ccdce32d30618b5f926199b0575c48' 'rebuild cx' 'build/cx'
# use case{}
at_revision 'd7d4bfa5ee92cdc13b5a6021983f39f120ce675a' 'rebuild cx' 'build/cx'
# remove ptr_offset
function rebuild_patch_ptr_offset {
    # has it, but doesn't use it
    echo "void* ptr_offset(void* p, int i) { return p + i; }" >> src/runtime.c
    rebuild "$@"
}
# progressively add a flag to the compiler invocation
function transition {
    TRANSITION="$1"
    mkdir build
    cp ../../build/cx build/cx
    cp -R ../../build/src build
    build/cx -Pcompiler:build/src -Pnext:src src/main.cx -o build/cx_1 -transition=$TRANSITION
    rm -rf .obj
    build/cx_1 -Pcompiler:src src/main.cx -o build/cx_2 -transition=$TRANSITION -macro-transition=$TRANSITION
    mv build/cx_2 build/cx
    rm -rf build/src
    cp -R src build/
}
# remove a flag that has become the default
function detransition {
    TRANSITION="$1"
    mkdir build
    cp ../../build/cx build/cx
    cp -R ../../build/src build
    build/cx -Pcompiler:build/src -Pnext:src src/main.cx -o build/cx_1 -transition=$TRANSITION -macro-transition=$TRANSITION
    rm -rf .obj
    build/cx_1 -Pcompiler:src src/main.cx -o build/cx_2
    mv build/cx_2 build/cx
    rm -rf build/src
    cp -R src build/
}
at_revision 'df8d6192c2ee16f5d3061e10d876452d0f9290e0' 'rebuild_patch_ptr_offset cx' 'build/cx'
at_revision 'df8d6192c2ee16f5d3061e10d876452d0f9290e0' 'rebuild cx' 'build/cx'
# add break/continue
at_revision 'd456abb76b28efc98f188e97a47ad6a2703a931a' 'rebuild cx' 'build/cx'
# change Context to struct
at_revision '109aed34bef153352c27a3db641fc446c13727b6' 'rebuild cx' 'build/cx'
# fix '/' to be sdiv
at_revision '49c99d8c805f84377fff747c51d20c840d695fb5' 'rebuild cx' 'build/cx'
# add 'abstract' keyword
at_revision '9b90edfd9eee4b088725cb811d76dd2eb36e009b' 'rebuild cx' 'build/cx'
# add char == char
at_revision '442e0c295870b44313f1d46973b2cca6a18eb84e' 'rebuild cx' 'build/cx'
# "is" syntax
at_revision '44f528fa50dd08ed4bd2b18dd847dd60286df88b' 'rebuild cx' 'build/cx'
# multivar declarations
at_revision '3e0e97794c6ee897dd142f7633131cfc15eb6a01' 'rebuild cx' 'build/cx'
# add this(this.i) syntax
at_revision '5429ed0d7f37a9405e12a414065937e9e8fe1024' 'rebuild cx' 'build/cx'
# add CompilerBase/CompilerImpl separation
at_revision 'f65bca79cad32b7e68facebb4b68e21905691f43' 'rebuild cx' 'build/cx'
# implicitConvertTo rename dance
at_revision '77666c50bfa2b3e13b373d50e20cfd3b8cd7d311' 'rebuild cx' 'build/cx'
# implicitConvertTo rename dance 1
at_revision 'ce7e5ad951e2f8cc332d48ef555d3af22c42687c' 'rebuild cx' 'build/cx'
# implicitConvertTo rename dance 2
at_revision '2366a53b8cb67b18df4ad7aeaf4f97ee59bd3448' 'rebuild cx' 'build/cx'
# CABI change to make structs > 8 bytes passed and returned as pointers
at_revision 'd76c8c948248ddbc3a069c3f265ec3a2fba66d23' 'rebuild cx' 'build/cx'
at_revision 'd76c8c948248ddbc3a069c3f265ec3a2fba66d23' 'transition new-cabi' 'build/cx'
at_revision '294fea36eb76c5c394fcac65f69dd05d62e80a93' 'detransition new-cabi' 'build/cx'
# array layout change: add a third pointer to the base of the array
at_revision '294fea36eb76c5c394fcac65f69dd05d62e80a93' 'transition new-arrays' 'build/cx'
at_revision '93d56a97db909a1e7a4d6fb6c0e30908479522fd' 'detransition new-arrays' 'build/cx'
# array base property
at_revision '3dc9aeb39c188a637be8f9357cc770b22f681fb3' 'rebuild cx' 'build/cx'
# binaryOp2
at_revision 'd0d0416723c643c157c42755ce10cc47f2dc4408' 'rebuild cx' 'build/cx'
# Type mangle()
at_revision '7ebcc2737910d81b96ed91696b52894472221d85' 'rebuild cx' 'build/cx'
# array literals
at_revision '0b77cb1931349283007dd015d8545b8660df881b' 'rebuild cx' 'build/cx'
# .name
at_revision 'dd6230de98348ec7612f2d30fa2802628bc46bbf' 'rebuild cx' 'build/cx'
# CompilerBase.parseType
at_revision 'e27b76b1eb6b212615f4ae98e41efeabdf6302ef' 'rebuild cx' 'build/cx'
# quasiquoting prep bootstrap fix
at_revision '5b5bca178ad3e1bc9c8937430ce838164c94082d' 'rebuild cx' 'build/cx'
# more quasiquoting
at_revision '04205ac9766be0ca4e31a128241163799615179e' 'rebuild cx' 'build/cx'
# [any], [all]
at_revision 'a2509315bc753abfb3170ecd31351564c92cde66' 'rebuild cx' 'build/cx'
# add quoting of typed var decl statements
at_revision '4430f4a47c5fe21e461d9c68cb7ed345330b10f9' 'rebuild cx' 'build/cx'
# class final
at_revision 'cdda324772cbe2d252f2c50d291d53f2ccb48be7' 'rebuild cx' 'build/cx'
# hash opt prep
at_revision '1bbc5c6f255095386994021458282196e96dc64e' 'rebuild cx' 'build/cx'
# cast()
at_revision 'f479cd617e9250b5347fa0d4222ef054898a76c2' 'rebuild cx' 'build/cx'
# refactoring stuff
at_revision '51003a75ae2b39a4d071032c6ce345305a74adda' 'rebuild cx' 'build/cx'
# bootstrap fix commit
at_revision '3f612a29adefd3e0edb59a32c309bd7394050f0f' 'rebuild cx' 'build/cx'
# intermediate commit: turn on array reference count incrementing
at_revision '8cd67cffc34930a84c5415169544b74845cfbb60' 'rebuild cx' 'build/cx'
# staticAlloca
at_revision '3cac13f97107ef000ae1f998e4f01b175b04edd3' 'rebuild cx' 'build/cx'
bash rebuild.sh
echo "=== build/cx from master ==="
