#!/usr/bin/env bash
set -euo pipefail
CX=build/cx
CXFLAGS="-Pcompiler:build/src"
CXFLAGS="${CXFLAGS} -Prunnable:test/runnable:compiler"
CXFLAGS="${CXFLAGS} -Pfail_compilation:test/fail_compilation:compiler"

num_total=$(ls -q test/runnable/*.cx test/fail_compilation/*.cx |wc -l)
build_failed=0
run_failed=0
build_crashed=0
falsely_succeeded=0
test_skipped=0

function test_enabled {
    test="$1"
    shift
    if [ $# -eq 0 ]; then return 0; fi
    while [ $# -gt 0 ]
    do
        if [[ "$test" == *"$1"* ]]; then return 0; fi
        shift
    done
    return 1
}

# runnable
mkdir -p build/test/runnable
while read file
do
    if ! test_enabled "$file" "$@"
    then
        test_skipped=$((test_skipped+1))
        continue
    fi
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
    if ! test_enabled "$file" "$@"
    then
        test_skipped=$((test_skipped+1))
        continue
    fi
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

num_total=$((num_total - test_skipped))
num_success=$((num_total - build_failed - run_failed - falsely_succeeded - build_crashed))

echo "Result:"
echo "  ${num_success}/${num_total} successful"
echo "  ${build_failed} failed to build"
echo "  ${run_failed} failed to run"
echo "  ${falsely_succeeded} built when they should have failed"
echo "  ${build_crashed} crashed the compiler instead of erroring"
echo "  ${test_skipped} tests were skipped"
[ $num_success -eq $num_total ]
