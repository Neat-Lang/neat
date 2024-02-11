#include <errno.h>
#ifdef linux
#include <dlfcn.h>
#ifdef __GLIBC__
#include <execinfo.h>
#endif
#include <pthread.h>
#include <sys/wait.h>
#include <unistd.h>
#endif
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct String
{
    size_t length;
    char *ptr;
    void *base;
};

struct StringArray
{
    size_t length;
    struct String *ptr;
    void *base;
};

// Arrays are passed as three separate parameters. This optimizes a lot better.
#define ARRAY_PARAM(type, valuetype, name) size_t name ## _length, type *name ## _ptr, void * name ## _base
#define ARRAY_VALUE(name) name ## _length, name ## _ptr, name ## _base

#define STRING_PARAM(name) ARRAY_PARAM(char, struct String, name)

struct String string_alloc(size_t length) {
    void *memory = malloc(sizeof(size_t) * 3 + length);
    ((size_t*) memory)[0] = 1; // references
    ((size_t*) memory)[1] = length; // capacity
    ((size_t*) memory)[2] = length; // used
    return (struct String) { length, memory + sizeof(size_t) * 3, memory };
}

void neat_runtime_lock_stdout(void);
void neat_runtime_unlock_stdout(void);

void print(STRING_PARAM(str)) {
    neat_runtime_lock_stdout();
    printf("%.*s\n", (int) str_length, str_ptr);
    fflush(stdout);
    neat_runtime_unlock_stdout();
}

void assert(int test) {
    if (!test) {
        fprintf(stderr, "Assertion failed! Aborting.\n");
        exit(1);
    }
}
int neat_runtime_ptr_test(void* ptr) { return !!ptr; }
int _arraycmp(void* a, void* b, size_t la, size_t lb, size_t sz) {
    if (la != lb) return 0;
    return memcmp(a, b, la * sz) == 0;
}
char* toStringz(STRING_PARAM(str)) {
    char *buffer = malloc(str_length + 1);
    strncpy(buffer, str_ptr, str_length);
    buffer[str_length] = 0;
    return buffer;
}

FILE* neat_runtime_stdout() {
    return stdout;
}

void neat_runtime_system(STRING_PARAM(command)) {
    char *cmd = toStringz(ARRAY_VALUE(command));
    int ret = system(cmd);
    if (ret != 0) fprintf(stderr, "command failed with %i\n", ret);
    assert(ret == 0);
    free(cmd);
}

int neat_runtime_system_iret(STRING_PARAM(command)) {
    char *cmd = toStringz(ARRAY_VALUE(command));
    int ret = system(cmd);
    free(cmd);
    return ret;
}

int neat_runtime_execbg(STRING_PARAM(command), ARRAY_PARAM(struct String, struct StringArray, arguments)) {
#ifdef linux
    int ret = fork();
    if (ret != 0) return ret;
    char *cmd = toStringz(ARRAY_VALUE(command));
    char **args = malloc(sizeof(char*) * (arguments_length + 2));
    args[0] = cmd;
    for (int i = 0; i < arguments_length; i++) {
        args[1 + i] = toStringz(arguments_ptr[i].length, arguments_ptr[i].ptr, arguments_ptr[i].base);
    }
    args[1 + arguments_length] = NULL;
    return execvp(cmd, args);
#else
    fprintf(stderr, "TODO!\n");
    exit(1);
#endif
}

#ifdef linux
bool neat_runtime_waitpid(int pid) {
    int wstatus;
    int ret = waitpid(pid, &wstatus, 0);
    if (ret == -1) fprintf(stderr, "waitpid() failed: %s\n", strerror(errno));
    return WIFEXITED(wstatus) && WEXITSTATUS(wstatus) == 0;
}

// No idea why this is necessary.
__attribute__((optnone))
__attribute__((optimize(0)))
bool neat_runtime_symbol_defined_in_main(STRING_PARAM(symbol)) {
    // even if a DL is loaded with RTLD_GLOBAL, main symbols are special.
    // so we want to avoid redefining symbols that are in the main program.
    void *main = dlopen(NULL, RTLD_LAZY);
    char *symbolPtr = toStringz(ARRAY_VALUE(symbol));
    void *sym = dlsym(main, symbolPtr);
    free(symbolPtr);
    dlclose(main);
    return sym ? true : false;
}

void neat_runtime_dlcall(STRING_PARAM(dlfile), STRING_PARAM(fun), void* arg) {
    void *handle = dlopen(toStringz(ARRAY_VALUE(dlfile)), RTLD_LAZY | RTLD_GLOBAL);
    if (!handle) fprintf(stderr, "can't open %.*s - %s\n", (int) dlfile_length, dlfile_ptr, dlerror());
    assert(!!handle);
    void *sym = dlsym(handle, toStringz(ARRAY_VALUE(fun)));
    if (!sym) fprintf(stderr, "can't load symbol '%.*s'\n", (int) fun_length, fun_ptr);
    assert(!!sym);

    ((void(*)(void*)) sym)(arg);
}
#endif

void *neat_runtime_alloc(size_t size) {
    return calloc(1, size);
}

extern void _run_unittests();

#ifndef NEAT_NO_MAIN
extern void MAIN(ARRAY_PARAM(struct String, struct StringArray, args));
#endif

int main(int argc, char **argv) {
    size_t args_length = argc;
    struct String *args_ptr = malloc(sizeof(struct String) * argc);
    void *args_base = NULL;
    for (int i = 0; i < argc; i++) {
        args_ptr[i] = (struct String) { strlen(argv[i]), argv[i] };
    }
    _run_unittests();
#ifndef NEAT_NO_MAIN
    MAIN(ARRAY_VALUE(args));
#else
    printf("Unittests run.\n");
#endif
    free(args_ptr);
    return 0;
}

// for debug breaks
void debug() { }

void print_backtrace()
{
#ifdef __GLIBC__
    void *array[20];
    int size = backtrace(array, 20);
    char **strings = backtrace_symbols(array, size);
    if (strings != NULL) {
        printf("Backtrace:\n");
        for (int i = 0; i < size; i++)
        printf("  %i: %s\n", i, strings[i]);
    }
    free(strings);
#endif
}

#define FATALERROR __attribute__((cold)) __attribute__((noinline)) __attribute__((noreturn))

void FATALERROR neat_runtime_refcount_violation(const char *desc, ptrdiff_t *ptr)
{
    printf("<%s: refcount logic violated: %zd at %p\n", desc, *ptr, ptr);
    print_backtrace();
    exit(1);
}

void FATALERROR neat_runtime_index_oob(size_t index)
{
    fprintf(stderr, "Array index out of bounds: %zd\n", index);
    exit(1);
}

void neat_runtime_refcount_inc(const char *desc, ptrdiff_t *ptr)
{
    // ptrdiff_t result = *ptr += 1;
    ptrdiff_t result = __atomic_add_fetch(ptr, 1, __ATOMIC_ACQ_REL);
    if (result <= 1)
    {
        neat_runtime_refcount_violation(desc, ptr);
    }
}

// FIXME remove
void neat_runtime_refcount_inc2(const char *desc, ptrdiff_t *ptr)
{
    return neat_runtime_refcount_inc(desc, ptr);
}

int neat_runtime_refcount_dec(const char *desc, ptrdiff_t *ptr)
{
    // ptrdiff_t result = *ptr -= 1;
    ptrdiff_t result = __atomic_sub_fetch(ptr, 1, __ATOMIC_ACQ_REL);
    if (result <= -1)
    {
        neat_runtime_refcount_violation(desc, ptr);
    }

    return result == 0;
}

// FIXME remove
void neat_runtime_refcount_dec2(const char *desc, ptrdiff_t *ptr)
{
    neat_runtime_refcount_dec(desc, ptr);
}

void neat_runtime_class_refcount_inc(void **ptr) {
    if (!ptr) return;
    neat_runtime_refcount_inc("class", (ptrdiff_t*) &ptr[1]);
}

void neat_runtime_class_refcount_dec(void **ptr) {
    if (!ptr) return;
    if (neat_runtime_refcount_dec("class", (ptrdiff_t*) &ptr[1]))
    {
        void (**vtable)(void*) = *(void(***)(void*)) ptr;
        void (*destroy)(void*) = vtable[1];
        destroy(ptr);
        free(ptr);
    }
}

void neat_runtime_intf_refcount_inc(void *ptr) {
    if (!ptr) return;
    size_t base_offset = **(size_t**) ptr;
    void **object = (void**) ((char*) ptr - base_offset);
    neat_runtime_refcount_inc("interface", (ptrdiff_t*) &object[1]);
}

void neat_runtime_intf_refcount_dec(void *ptr) {
    if (!ptr) return;
    size_t base_offset = **(size_t**) ptr;
    void **object = (void**) ((char*) ptr - base_offset);
    if (neat_runtime_refcount_dec("interface", (ptrdiff_t*) &object[1])) {
        void (**vtable)(void*) = *(void(***)(void*)) object;
        void (*destroy)(void*) = vtable[1];
        destroy(object);
        free(object);
    }
}

void neat_runtime_refcount_set(size_t *ptr, size_t value) {
    // *ptr = value;
    __atomic_store(ptr, &value, __ATOMIC_RELEASE);
}

int neat_runtime_errno() { return errno; }

#ifdef linux
pthread_mutex_t stdout_lock;
#endif

__attribute__((constructor)) void neat_runtime_stdout_lock_init(void) {
#ifdef linux
    pthread_mutex_init(&stdout_lock, NULL);
#endif
}

void neat_runtime_lock_stdout(void) {
#ifdef linux
    pthread_mutex_lock(&stdout_lock);
#endif
}

void neat_runtime_unlock_stdout(void) {
#ifdef linux
    pthread_mutex_unlock(&stdout_lock);
#endif
}
