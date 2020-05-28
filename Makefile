STAGE1_SRC = $(shell find src/stage1 -name \*.d)
DSHOULD_INCLUDES = $(shell dub fetch dshould 1>&2 && dub build dshould 1>&2 && \
	dub describe dshould |\
	jq -r '[[.. |.importPaths? |arrays[]] |unique[] |select(contains(".dub"))] |map("-I"+.) |join(" ")')
DFLAGS = -g -odbuild -Iinclude -Isrc -Isrc/stage1 -Iinclude/boilerplate/src ${DSHOULD_INCLUDES} -L-Lbuild

.PHONY: test

default: build/stage1 build/stage1_test

build/libstage1.a: src/stage1_libs.d
	ldc2 $< -of$@ ${DFLAGS} ${DSHOULD_INCLUDES} -i -lib

build/stage1: ${STAGE1_SRC} build/libstage1.a
	ldc2 ${STAGE1_SRC} -of$@ ${DFLAGS} -L-lstage1

build/stage1_test: ${STAGE1_SRC} build/libstage1.a
	ldc2 ${STAGE1_SRC} -of$@ ${DFLAGS} -L-lstage1 -main -unittest

test: build/stage1
	build/stage1 -Isrc/stage2 hello.cx
	build/stage1 -Isrc/stage2 parser.cx
	build/stage1 -Isrc/stage2 ack.cx
