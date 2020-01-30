#!/bin/sh
mkdir build -p
ldc2 -g -i -odbuild hello.d -ofbuild/hello -Iinclude/boilerplate/src
