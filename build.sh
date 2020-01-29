#!/bin/sh
mkdir build -p
ldc2 -i -odbuild hello.d -ofbuild/hello -Iinclude/boilerplate/src
