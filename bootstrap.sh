#!/usr/bin/env bash
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
    language="cx"
    if [ "$output" == "build/neat" ]; then language="neat"; fi

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
    set -x
    $build
    set +x
    cd ../..
    cp build/$rev/$output build/$language
    # bleeeh this should not be here, this is not generic, but meh
    if [ -d build/$rev/build/src ]; then
        rm -rf build/src
        cp -R build/$rev/build/src build/
    fi
    if [ -f build/$rev/build/$language.ini ]; then
        cp build/$rev/build/$language.ini build/
    fi
    rm -rf build/$rev

    # now create the archive
    echo "- saving bootstrap archive $archive"
    tar cf "$archive" build

    echo "=== build/$language from $rev ==="
    echo
}
function dbootstrap {
    make build/stage1
    echo "- stage1/stage2/stage2"
    build/stage1 -Isrc/stage2 main.cx -- -Isrc/stage2 src/stage2/main.cx -o build/stage2
}
function rebuild {
    mkdir -p build
    if [ -e "../../build/cx" ]; then
        cp ../../build/cx build/$1
    else
        cp ../../build/neat build/$1
    fi
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
    COMPILER="neat"
    EXT="nt"
    if [ -f "../../build/cx" ]; then
        COMPILER="cx"
        EXT="cx"
    fi
    cp ../../build/$COMPILER build/$COMPILER
    cp -R ../../build/src build
    build/$COMPILER -Pcompiler:build/src -Pnext:src src/main.$EXT -o build/stage1 -transition=$TRANSITION $@
    rm -rf .obj
    build/stage1 -Pcompiler:src src/main.$EXT -o build/stage2 -transition=$TRANSITION -macro-transition=$TRANSITION $@
    mv build/stage2 build/$COMPILER
    rm -rf build/src
    cp -R src build/
}
# remove a flag that has become the default
function detransition {
    TRANSITION="$1"
    shift
    mkdir build
    if [ -f "../../build/cx" ]; then
        COMPILER="cx"
        EXT="cx"
        cp -R ../../build/src build
    else
        COMPILER="neat"
        EXT="nt"
        # Uhhhhhh. It selects the wrong files for some reason.
        # Something is fucky & broken. But it's 7am on a sunday and I cba.
        # TODO condition this on the generation count once we fix it.
        cp -R src build
    fi
    cp ../../build/$COMPILER build/$COMPILER
    build/$COMPILER -Pcompiler:build/src -Pnext:src src/main.$EXT -o build/stage1 \
        -transition=$TRANSITION -macro-transition=$TRANSITION $@
    rm -rf .obj
    build/stage1 -Pcompiler:src src/main.$EXT -o build/stage2 $@
    mv build/stage2 build/$COMPILER
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
# add __GENERATION__ at 1
at_revision 'a588979560782f49f784f02c0f4f4cfed43b32db' 'rebuild cx' 'build/cx'
# support type conversion on array ~ element
at_revision '5c9e121ae34b0ebe03b0567a7e4273cbd1be75b3' 'rebuild cx' 'build/cx'
# accessDecl(CompilerBase) part 1
at_revision 'd2ca576122c04360f1dc2acea39c93996d15795b' 'rebuild cx' 'build/cx'
# cast(char) int, cast(int) char
at_revision '1ffb69395d42975da6d087579c0669182560e94e' 'rebuild cx' 'build/cx'
# add \xHH
at_revision '318cf76dd8c488471d365ead0576b2b51b3e7d83' 'rebuild cx' 'build/cx'
# fix template emission
at_revision '495eec5f6de89ed2289bc26ed37e2ada39f9da95' 'rebuild cx' 'build/cx'
# tuples, tuple names, tuple refs
at_revision '3f4925db6f8e3f2f1d48e4e532aa144be7c5214a' 'rebuild cx' 'build/cx'
# UFCS!
at_revision '7acee9ee1b5991e08d89c568e3a50205ac12b75a' 'rebuild cx' 'build/cx'
# executable as main argument
at_revision '9ce663e39be09838e6a8ca397ff0909cc61e55ed' 'rebuild cx' 'build/cx'
# used when the contents of macros have to change between compiler versions, but there's no change in functionality
function macro_transition {
    mkdir build
    language="cx"
    ext="cx"
    if [ -e "../../build/neat" ]; then language="neat"; ext="nt"; fi
    cp ../../build/$language build/$language

    NEXT=compiler$(($(build/$language -print-generation) + 1))

    mkdir build/backup
    cp -R src/$language/macros/ build/backup/
    cp -R ../../build/src/ build/
    # use old macros for first round
    cp -R ../../build/src/$language/macros/ src/$language/
    build/$language -next-generation -Pcompiler:build/src -P$NEXT:src src/main.$ext -o build/${language}_1 $@
    # use new macros even for previous-generation imports
    cp -R build/backup/macros/ src/$language/
    cp -R build/backup/macros/ build/src/$language/
    build/${language}_1 -Pcompiler:src src/main.$ext -o build/${language}_2 $@
    mv build/${language}_2 build/$language
    rm -rf build/src
    rm -rf build/backup
    cp -R src build/
}
# switch override `Type type()` to `Type type;` field in `Expression`.
at_revision 'aec1a7c0f3804f6bcd28227275f3b15516a8d565' 'macro_transition' 'build/cx'
# fix context scope flag in import namespace
at_revision '1f69f70de69eaf651a9b726cc5dd775931407e10' 'rebuild cx' 'build/cx'
# support cx.ini
at_revision 'fd3eb8998a26e96ea95ff84ccb6c0a73a19c0925' 'rebuild cx' 'build/cx'
# allow aliasing types
at_revision '2a3e93bfcbaacd98873e37c2e3a79b4ea323b9c4' 'rebuild cx' 'build/cx'
# fix imports that are never used except at function level
at_revision 'dc04c08b0213c017ac2a7e06160b85510307e838' 'rebuild cx' 'build/cx'
# object cache, fallback for missing filename
at_revision '607e4dd167697c89d2d1bcc2a991337c382cbdb7' 'rebuild cx' 'build/cx'
# move Either classes into the compiler
at_revision 'cde31c3b08efd0146379488361782b22f385c917' 'rebuild cx' 'build/cx'
# Either tuple syntax
at_revision 'a7b0f886bb2d548d79206e634ab24ada76d04732' 'rebuild cx' 'build/cx'
# symbol identifiers, unnamed-variable destructuring
at_revision 'd3ad0e8bf7f767303b598c108dcf3e3e3769fb43' 'rebuild cx' 'build/cx'
# astDeclareVar mut transition 1
at_revision '8f8a5166109cedc95be515500d34b65565f1221c' 'rebuild cx' 'build/cx'
# astDeclareVar mut transition 2
at_revision '76d02ada9a5123b9683703661da6c2f52ed4f67b' 'rebuild cx' 'build/cx'
# arguments can be mut
at_revision 'b44d62c2a601e4a9ee101e11517e8d8bbb11c3de' 'macro_transition' 'build/cx'
# either expr case return
at_revision '475bce773390ca3ebb34fb0ced7a8e03188be9df' 'rebuild cx' 'build/cx'
# fix either statement to not double-evaluate its lhs
at_revision '151b7a4700eed13a25d5e4ac7cbed5cf56104bb2' 'rebuild cx' 'build/cx'
# tuple refcounting
at_revision '9af0785adc3a2295cfd4d180aee90337631bced9' 'rebuild cx' 'build/cx'
# no-op cxruntime_cache_clear, fix hash string alloc
at_revision '12bd0030e530b8431f57693ddc3137a7d3484049' 'rebuild cx' 'build/cx'
# implconv tuples to tuples
at_revision '119fca3f605d927330805b843672506dbe38988e' 'rebuild cx' 'build/cx'
# a++, ++a
at_revision 'f705834e763c62d9750644244ad4c3fff8391894' 'rebuild cx' 'build/cx'
# static struct methods
at_revision '80ec1698086de9692b478283928f796ba08e5a15' 'rebuild cx' 'build/cx'
# named arg on classes 1
at_revision '4ac33cfc1a042e3fff7e6eaf468b3c58a0c24491' 'macro_transition' 'build/cx'
# __HERE__ reloc
at_revision 'c9b5bbcfffecf0d0d80e5fba45310f035b26abd0' 'rebuild cx' 'build/cx'
# fix <<, >> impl
at_revision 'cef5b8e69e71d93c6bcd52d9eb4c79913d35c532' 'rebuild cx' 'build/cx'
# trivial ubyte
at_revision '29aa4d3ced3dd41266a224ec93104cee8f1f8183' 'rebuild cx' 'build/cx'
# unsigned shift right
at_revision '24f70228d533366b2f6626fb757091512b469b15' 'rebuild cx' 'build/cx'
# -I for cimport
at_revision '96bcb2def5743ec3f0792c5cb6d92b7be490def1' 'rebuild cx' 'build/cx'
# rename Argument to Parameter
at_revision 'a7bc4cdf1e0a7ed7a8adf78bd389c9a2e025ce9e' 'macro_transition' 'build/cx'
# move call to plainCall, callWithLifetime to call
at_revision 'f62ae18850737d210d8e083135abaf4ab7b66b8f' 'macro_transition' 'build/cx'
# CallMacroArgs takes ASTArgument
at_revision '519ef7a947efe865833d3b6a6a7e4618f81bef75' 'macro_transition' 'build/cx'
# unittest {}
at_revision '9d196c27e9230554192811cf0cc6d317bf610e38' 'rebuild cx' 'build/cx'
# fix empty array literal, allow assert macro in std
at_revision '40971abeb6efa53e2fe6618927b2ea7572927d02' 'rebuild cx' 'build/cx'
# quote ASTEitherDecl, ASTSymbolIdentifier, ASTEitherCaseStmt, ASTEitherCaseExpr
at_revision '68ba0902ebab759e4f251307ed93acbab6211a45' 'rebuild cx' 'build/cx'
# name=value for new calls
at_revision '23f10d32c39779ff77fbdab218e19ce5b40aa553' 'rebuild cx' 'build/cx'
# transition Loc/ReLoc -> Loc with row/column directly
at_revision '5a9e0b194c2a5fa394c3ae4338b7e36b48e549e8' 'macro_transition' 'build/cx'
# add Loc parameter to lookup()
at_revision '38ba877af6c2313437595bb54c3f2c729922d930' 'macro_transition' 'build/cx'
# Reorg some stuff: for some reason, we crash without this.
at_revision 'da674e882c5ab0529d5c183812b2b1b0bb08b6a2' 'rebuild cx' 'build/cx'
function lang_transition_1 {
    mkdir -p build
    cp ../../build/cx build/cx
    FAST=1 rebuild neat
    rm build/cx
    # this is not clean lol
    rm ../../build/cx ../../build/cx.ini
    echo "-syspackage compiler:src" > build/neat.ini
}
function lang_transition_2 {
    mkdir build
    cp ../../build/neat build/neat
    cp -R ../../build/src build
    cp -R src/neat/ build/src/
    sed -i -e 's/-O//' rebuild.sh
    bash rebuild.sh
}
function lang_transition_3 {
    mkdir build
    cp ../../build/neat build/neat
    cp -R ../../build/src build
    cp -R src/neat/ build/src/
    sed -i -e 's/-O//' rebuild.sh
    # use new runtime.c
    cp src/runtime.c build/src/runtime.c
    # proxy some old function names to the new ones
    cat <<EOT >>build/src/runtime.c
int cxruntime_refcount_dec(struct String s, long long int *ptr) { return neat_runtime_refcount_dec(s, ptr); }
void cxruntime_refcount_inc(struct String s, long long int *ptr) { return neat_runtime_refcount_inc(s, ptr); }
void *cxruntime_alloc(size_t size) { return neat_runtime_alloc(size); }
void *cxruntime_cache_get(int key) { return neat_runtime_cache_get(key); }
void cxruntime_cache_set(int key, void *ptr, void(*free)(void*)) { return neat_runtime_cache_set(key, ptr, free); }
int cxruntime_cache_isset(int key) { return neat_runtime_cache_isset(key); }
int cxruntime_atoi(struct String str) { return neat_runtime_atoi(str); }
float cxruntime_atof(struct String str) { return neat_runtime_atof(str); }
struct String cxruntime_itoa(int i) { return neat_runtime_itoa(i); }
struct String cxruntime_ftoa(float f) { return neat_runtime_ftoa(f); }
struct String cxruntime_ltoa(long long l) { return neat_runtime_ltoa(l); }
struct String cxruntime_ftoa_hex(float f) { return neat_runtime_ftoa_hex(f); }
struct String cxruntime_ptr_id(void* ptr) { return neat_runtime_ptr_id(ptr); }
bool cxruntime_symbol_defined_in_main(struct String symbol) { return neat_runtime_symbol_defined_in_main(symbol); }
EOT
    bash rebuild.sh
}
# rename cx to NeatLang
at_revision '3bb29dbac77de3b27dc15b28730f07c415cbb628' 'lang_transition_1' 'build/neat'
# rename cx to NeatLang, part 2
at_revision 'e658d57ba621e761a8f6d92a1d78b398ebcce2bd' 'lang_transition_2' 'build/neat'
# rename cx to NeatLang, part 3
at_revision 'f9ef0cb5a2ea906edc125252cd7c8217836df3ae' 'lang_transition_3' 'build/neat'
# format string prep: '$' is escapable
at_revision 'ffab3ed0a6debabd56b042ec8d172ed43bc77917' 'rebuild neat' 'build/neat'
# Implement format strings.
at_revision 'e14ccdde5f8d7fe07fb3917666ccfa54a6641c6e' 'rebuild neat' 'build/neat'
# private/public, quoting ASTFunctionPointer
at_revision '62881ff0a2337a0ea19d47177a377a7a715ea22a' 'rebuild neat' 'build/neat'
# class vtable layout change, prep for interfaces
at_revision '1e4827c2359a39936d1d1ddc5f93cb1995fc776b' 'rebuild neat' 'build/neat'
at_revision '1e4827c2359a39936d1d1ddc5f93cb1995fc776b' 'transition new-vtable' 'build/neat'
at_revision '4bb30a2763f232da7e78a47f321fe56e8d3d2172' 'detransition new-vtable' 'build/neat'
# struct quoting, tuple type quoting, sizeof quoting, tuple quoting, assert quoting
at_revision '801e58b5527560ab771a702374eded61cbc036a7' 'rebuild neat' 'build/neat'
# add basic hashmap type (no ops, intermediate step so we can quote K[V])
# add xor operator, voidLiteral, format string quoting
at_revision 'f34c7af30fedc1834459f605dd37f0608db61db4' 'rebuild neat' 'build/neat'
# hashmaps, prep work for Either 'fail' stage 1
at_revision '0a4cd2dbec917923fe3c1c8735348b94dda63131' 'rebuild neat' 'build/neat'
# Either 'fail' stage 2
at_revision 'ca7c71bf59db657a7d8d5bd9bbcb5b546a0cab38' 'rebuild neat' 'build/neat'

# unpack the last tagfile
unpack_tagfile

bash rebuild.sh
echo "=== build/neat from master ==="
