CFLAGS = -g -O2 -Wall -Werror -Wfatal-errors -Iinclude -Lbuild -lcx
DFLAGS = -Iinclude -Iinclude/boilerplate/src
LIB_SOURCES = $(shell find lib -name \*.c)
LIB_OBJECTS = $(patsubst %.c,build/%.o,$(LIB_SOURCES))
HEADERS = $(shell find include -name \*.h)
BACKEND_SRC = $(shell find src/backend -name \*.d)
DSHOULD_INCLUDES = $(shell dub fetch dshould 1>&2 && dub build dshould 1>&2 && \
	dub describe dshould |\
	jq -r '[[.. |.importPaths? |arrays[]] |unique[] |select(contains(".dub"))] |map("-I"+.) |join(" ")')

default: build/interpret build/build_ack build/hello build/backend_test

$(LIB_OBJECTS): build/%.o: %.c $(HEADERS)
	gcc $(CFLAGS) -c $< -o $@

$(LIB_OBJECTS): | build/lib

build/lib:
	mkdir -p $@

build/libcx.a: $(LIB_OBJECTS)
	ar rcs $@ $(LIB_OBJECTS)

build/build_ack: build/libcx.a build_ack.c
	gcc build_ack.c $(CFLAGS) -o $@

build/interpret: build/libcx.a interpret.c
	gcc interpret.c $(CFLAGS) -o $@

build/hello: build/libcx.a hello.d
	ldc2 -g -i -odbuild hello.d -ofbuild/hello ${DFLAGS} -L-Lbuild -L-lcx

build/libbackend_deps.a: backend_deps.d
	ldc2 -g -i -lib -odbuild backend_deps.d -ofbuild/libbackend_deps.a ${DFLAGS} ${DSHOULD_INCLUDES}

build/backend_test: ${BACKEND_SRC} build/libbackend_deps.a
	ldc2 -g -odbuild -ofbuild/backend_test -main -unittest ${BACKEND_SRC} -L-Lbuild -L-lbackend_deps ${DFLAGS} ${DSHOULD_INCLUDES}
