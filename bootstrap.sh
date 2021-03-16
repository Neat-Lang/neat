#!/bin/sh
set -eu

rm -rf build
mkdir build
mkdir -p .bootcache

function unpack_tagfile {
    tagfile="build/archive"
    if [ -f "$tagfile" ]
    then
        # unpack the previous archive
        unpack_archive=$(cat "$tagfile")
        rm "$tagfile"
        echo "- restoring bootstrap archive $unpack_archive"
        tar xf "$unpack_archive"
    fi
}

# Since the language is self-hosting, we require a copy of the compiler in order to
# produce another copy. To sidestep this circular requirement, we check out a sequence
# of historic git revisions that did have a working bootstrap compiler, and use them to
# bootstrap up to the present.
# Note that you need a copy of LDC around 2.089.1-ish in the path.
function at_revision {
    rev=$1
    build=$2
    output=$3
    archive=".bootcache/"$(echo "$1 $2" |sed -e 's/[^a-zA-Z0-9]/_/g')".tar.xz"
    tagfile="build/archive"

    if [ -f "$archive" ]
    then
        # prepare to use the cached version of the archive
        echo "$archive" > "$tagfile"
        return 0
    fi

    # archive doesn't exist - but maybe the tagfile does?
    unpack_tagfile

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

    # now create the archive
    echo "- saving bootstrap archive $archive"
    tar cf "$archive" build

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
    shift
    mkdir build
    cp ../../build/cx build/cx
    cp -R ../../build/src build
    build/cx -Pcompiler:build/src -Pnext:src src/main.cx -o build/cx_1 -transition=$TRANSITION $@
    rm -rf .obj
    build/cx_1 -Pcompiler:src src/main.cx -o build/cx_2 -transition=$TRANSITION -macro-transition=$TRANSITION $@
    mv build/cx_2 build/cx
    rm -rf build/src
    cp -R src build/
}
# remove a flag that has become the default
function detransition {
    TRANSITION="$1"
    shift
    mkdir build
    cp ../../build/cx build/cx
    cp -R ../../build/src build
    build/cx -Pcompiler:build/src -Pnext:src src/main.cx -o build/cx_1 \
        -transition=$TRANSITION -macro-transition=$TRANSITION $@
    rm -rf .obj
    build/cx_1 -Pcompiler:src src/main.cx -o build/cx_2 $@
    mv build/cx_2 build/cx
    rm -rf build/src
    cp -R src build/
}
FLAGS=""
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
# classes with reference count
at_revision '158d1231313d2db1c68ffa2c530e328205a074da' 'rebuild cx' 'build/cx'
at_revision '158d1231313d2db1c68ffa2c530e328205a074da' 'transition new-classes' 'build/cx'
at_revision '58e2e874c16641455fbf78db05a7222168e6659c' 'detransition new-classes' 'build/cx'
# classes with __release method
at_revision 'e791bb8c1b9047cd25c2b75a4c05730a2a27e2ff' 'rebuild cx' 'build/cx'
at_revision 'e791bb8c1b9047cd25c2b75a4c05730a2a27e2ff' 'transition gen-release-method' 'build/cx'
at_revision 'b7c2e88728079cfb67ddab7f8b57227736e1c84b' 'detransition gen-release-method' 'build/cx'
# idk, something performance
at_revision '104c043018a8ba912faf340c0dfd0abe893b59a7' 'rebuild cx' 'build/cx'
# class lifetimes
at_revision 'af1606e2c0dbc214f99ba6bb83c5899a192ab2b6' 'rebuild cx' 'build/cx'
# either lifetimes
at_revision 'b962a396dd58bf0068cec16452d242362cb8fbc4' 'rebuild cx' 'build/cx'
# fix bootstrapping for array concat
at_revision '435fb780bda8a134597f04d3f28989b30077e80a' 'rebuild cx' 'build/cx'
# fix bootstrapping for refcounts (disable free)
at_revision 'dfb9db03891d9718a0d93dafbfb9c5e6302e14ff' 'rebuild cx' 'build/cx'
# actual refcounts
at_revision '12c19f21cd81f978e8292861288546406b9e68fe' 'rebuild cx' 'build/cx'
# reenable some stuff I forgot
at_revision '4c25468bd67660b2390fcdb2f2cda35b4e4a6954' 'rebuild cx' 'build/cx'
# array[$]
at_revision '5ac30c9c47a4d25a810f616249581d87adc99be1' 'rebuild cx' 'build/cx'
# fix 'this' access for nested functions
at_revision '1e5ee234e431a82c406d7dd1b654ad539c0c7141' 'rebuild cx' 'build/cx'
# transition: add Context parameter to implicitConvertTo
at_revision '94efdb9b9a87bdab96ad154d7d7527b19832a189' 'rebuild cx' 'build/cx'
# transition 2: add Context parameter to implicitConvertTo
at_revision '2534fa70241b08338543e4711b727bcf148854f8' 'rebuild cx' 'build/cx'
# at enums
at_revision '507a440728862a3a771e83619bdfd23000ddab08' 'rebuild cx' 'build/cx'
# make ownership an enum
at_revision '1c3e540a528c0cfb51daa171dabdd3fdd6e8259b' 'rebuild cx' 'build/cx'
# array slice quoting
at_revision '8704d9e17eafc7a2b7aa36e7d6f46fe5cc59d88e' 'rebuild cx' 'build/cx'
# once macro
at_revision '2c349743d50818dd682279c1b8133f9729cd2c50' 'rebuild cx' 'build/cx'
# implement with()
at_revision 'c025ace37cc708342a9a4bc4523afdcf9dbca74e' 'rebuild cx' 'build/cx'
# __instanceof compares classinfo instead of class name
at_revision '8ea062f885d198ce15a67587a5e78caaabdac1f4' 'rebuild cx' 'build/cx'
FLAGS="${FLAGS} --HACK-rename-next-to-compiler"
at_revision '8ea062f885d198ce15a67587a5e78caaabdac1f4' \
    "transition instanceofClassinfo $FLAGS" 'build/cx'
at_revision 'de774c02f7ab9246458f0a248867ddf26cd4dc49' \
    "detransition instanceofClassinfo $FLAGS" 'build/cx'
# if (vardecl)
at_revision '1db795ea97dc06123e3285c40a167bce16ca8905' 'rebuild cx' 'build/cx'
# export binary hash
at_revision '997b4702ebcb96f7b2e323993458bd712bfccb52' 'rebuild cx' 'build/cx'
# apply binary hash to objects
at_revision '28e52db8efba8505628014965f1f9c45cd2ae38c' 'rebuild cx' 'build/cx'
# remove ASTType, stage 1
at_revision 'e020aacbd3a027d5b4f69ec66e5ab1e39ac5b8be' 'rebuild cx' 'build/cx'
# add class templates
at_revision 'a03b948874b45bfed49c887ee0097406bc115b4a' 'rebuild cx' 'build/cx'
# implicit function calls
at_revision '2a6c1407465c2e15ad3a8d16a29d388808fe09f0' 'rebuild cx' 'build/cx'
# exprWithScratchspace
at_revision 'fdfb6a98d45883f4ccd50933ddf6753209dccb6a' 'rebuild cx' 'build/cx'
# Either case: return new Either, impl convert
at_revision '06ce1d7b9dc46db395b70cde61127d2f00bdac22' 'rebuild cx' 'build/cx'
# $stmt statementvar;
at_revision '8c6579ffd1ca48a954bf50eb1fbcd801abb18e37' 'rebuild cx' 'build/cx'
# extended for loops
at_revision '30aaa695621a169ea8e345bc55a7e55e08668b6c' 'rebuild cx' 'build/cx'

# unpack the last tagfile
unpack_tagfile

bash rebuild.sh
echo "=== build/cx from master ==="
