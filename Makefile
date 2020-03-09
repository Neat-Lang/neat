CFLAGS = -g -O2 -Wall -Werror -Wfatal-errors -Iinclude -Lbuild -lcx
LIB_SOURCES = $(shell find lib -name \*.c)
LIB_OBJECTS = $(patsubst %.c,build/%.o,$(LIB_SOURCES))
HEADERS = $(shell find include -name \*.h)

default: build/interpret build/build_ack build/hello

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
	ldc2 -g -i -odbuild hello.d -ofbuild/hello -Iinclude/boilerplate/src -L-Lbuild -L-lcx
