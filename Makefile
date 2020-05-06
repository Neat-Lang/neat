DFLAGS = -Iinclude -Iinclude/boilerplate/src
BACKEND_SRC = $(shell find src/backend -name \*.d)
DSHOULD_INCLUDES = $(shell dub fetch dshould 1>&2 && dub build dshould 1>&2 && \
	dub describe dshould |\
	jq -r '[[.. |.importPaths? |arrays[]] |unique[] |select(contains(".dub"))] |map("-I"+.) |join(" ")')

default: build/hello build/backend_test

build/hello: ${BACKEND_SRC} build/libbackend_deps.a src/hello.d
	ldc2 -g -i -odbuild src/hello.d -ofbuild/hello -Isrc ${DFLAGS} -L-Lbuild -L-lbackend_deps ${DSHOULD_INCLUDES}

build/libbackend_deps.a: src/backend_deps.d
	ldc2 -g -i -lib -odbuild src/backend_deps.d -Isrc -ofbuild/libbackend_deps.a ${DFLAGS} ${DSHOULD_INCLUDES}

build/backend_test: ${BACKEND_SRC} build/libbackend_deps.a
	ldc2 -g -odbuild -Isrc -ofbuild/backend_test -main -unittest ${BACKEND_SRC} -L-Lbuild -L-lbackend_deps ${DFLAGS} ${DSHOULD_INCLUDES}
