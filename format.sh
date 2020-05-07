#!/bin/sh
FLAGS="--keep_line_breaks=true --align_switch_statements=false"
dub -q run dfmt -- $FLAGS --inplace $(find src -name \*.d)
