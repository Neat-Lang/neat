#!/bin/bash
set -euo pipefail
CX=build/cx
CXFLAGS="-Pcompiler:build/src"
CXFLAGS="${CXFLAGS} -Prunnable:test/runnable:compiler"
CXFLAGS="${CXFLAGS} -Pfail_compilation:test/fail_compilation:compiler"

num_total=$(ls test/runnable test/fail_compilation |wc -l)
build_failed=0
run_failed=0
build_crashed=0
falsely_succeeded=0

# runnable
mkdir -p build/test/runnable
while read file
do
    echo test/runnable/"$file"...
    executable=build/test/runnable/"$file"
    if ! $CX $CXFLAGS test/runnable/"$file" -o "$executable" 2>&1 |cat>build/out.txt
    then
        build_failed=$((build_failed+1))
        cat build/out.txt
    elif ! "$executable"
    then
        run_failed=$((run_failed+1))
    fi
done < <(ls test/runnable)

# fail_compilation
# tests should fail with an exit code, not a segfault
mkdir -p build/test/fail_compilation
while read file
do
    echo test/fail_compilation/"$file"...
    executable=build/test/fail_compilation/"$file"
    set +e
    $CX $CXFLAGS test/fail_compilation/"$file" -o "$executable" 2>&1 |cat>build/out.txt
    EXIT=$?
    set -e
    if [ $EXIT -eq 0 ]; then
        falsely_succeeded=$((falsely_succeeded+1))
        cat build/out.txt
        echo "Error expected but not found!"
    elif [ $EXIT -gt 128 ]; then
        # signal
        build_crashed=$((build_crashed+1))
        cat build/out.txt
    fi
done < <(ls test/fail_compilation)

num_success=$((num_total - build_failed - run_failed - falsely_succeeded - build_crashed))

echo "Result:"
echo "  ${num_success}/${num_total} successful"
echo "  ${build_failed} failed to build"
echo "  ${run_failed} failed to run"
echo "  ${falsely_succeeded} built when they should have failed"
echo "  ${build_crashed} crashed the compiler instead of erroring"
[ $num_success -eq $num_total ]
