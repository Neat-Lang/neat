#!/bin/bash
set -euo pipefail
mkdir -p build/test/runnable
num_runnable=$(ls test/runnable |wc -l)
build_failed=0
run_failed=0
while read file
do
    echo test/runnable/"$file"...
    executable=build/test/runnable/"$file"
    if ! build/cx -Isrc -Itest/runnable test/runnable/"$file" -o "$executable" \
        2>&1 |cat>build/out.txt
    then
        build_failed=$((build_failed+1))
        cat build/out.txt
    elif ! "$executable"
    then
        run_failed=$((run_failed+1))
    fi
done < <(ls test/runnable)
num_success=$((num_runnable - build_failed - run_failed))
echo "Result: ${num_success} successful, ${build_failed} failed to build, ${run_failed} failed to run."
[ $num_success -eq $num_runnable ]
