CFLAGS = -g -O2 -Wall -Werror -Wfatal-errors -Iinclude -Lbuild -lcx
LIB_SOURCES = $(shell find lib -name \*.c)
LIB_OBJECTS = $(patsubst %.c,build/%.o,$(LIB_SOURCES))

default: build/interpret build/build_ack

build build/lib:
	mkdir -p $@

$(LIB_OBJECTS): build/%.o: %.c build/lib
	gcc $(CFLAGS) -c $< -o $@

build/libcx.a: build $(LIB_OBJECTS)
	ar rcs $@ $(LIB_OBJECTS)

build/build_ack: build build/libcx.a build_ack.c
	gcc build_ack.c $(CFLAGS) -o $@

build/interpret: build build/libcx.a interpret.c
	gcc interpret.c $(CFLAGS) -o $@
