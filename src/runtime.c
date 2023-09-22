#include <dlfcn.h>
#include <errno.h>
#ifdef __GLIBC__
#include <execinfo.h>
#endif
#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

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

struct String string_alloc(size_t length) {
    void *memory = malloc(sizeof(size_t) * 3 + length);
    ((size_t*) memory)[0] = 1; // references
    ((size_t*) memory)[1] = length; // capacity
    ((size_t*) memory)[2] = length; // used
    return (struct String) { length, memory + sizeof(size_t) * 3, memory };
}

void neat_runtime_lock_stdout(void);
void neat_runtime_unlock_stdout(void);

void print(struct String str) {
    neat_runtime_lock_stdout();
    printf("%.*s\n", (int) str.length, str.ptr);
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
char* toStringz(struct String str) {
    char *buffer = malloc(str.length + 1);
    strncpy(buffer, str.ptr, str.length);
    buffer[str.length] = 0;
    return buffer;
}

FILE* neat_runtime_stdout() {
    return stdout;
}

void neat_runtime_system(struct String command) {
    char *cmd = toStringz(command);
    int ret = system(cmd);
    if (ret != 0) fprintf(stderr, "command failed with %i\n", ret);
    assert(ret == 0);
    free(cmd);
}

int neat_runtime_system_iret(struct String command) {
    char *cmd = toStringz(command);
    int ret = system(cmd);
    free(cmd);
    return ret;
}

int neat_runtime_execbg(struct String command, struct StringArray arguments) {
    int ret = fork();
    if (ret != 0) return ret;
    char *cmd = toStringz(command);
    char **args = malloc(sizeof(char*) * (arguments.length + 2));
    args[0] = cmd;
    for (int i = 0; i < arguments.length; i++) {
        args[1 + i] = toStringz(arguments.ptr[i]);
    }
    args[1 + arguments.length] = NULL;
    return execvp(cmd, args);
}

bool neat_runtime_waitpid(int pid) {
    int wstatus;
    int ret = waitpid(pid, &wstatus, 0);
    if (ret == -1) fprintf(stderr, "waitpid() failed: %s\n", strerror(errno));
    return WIFEXITED(wstatus) && WEXITSTATUS(wstatus) == 0;
}

// No idea why this is necessary.
__attribute__((optnone))
__attribute__((optimize(0)))
bool neat_runtime_symbol_defined_in_main(struct String symbol) {
    // even if a DL is loaded with RTLD_GLOBAL, main symbols are special.
    // so we want to avoid redefining symbols that are in the main program.
    void *main = dlopen(NULL, RTLD_LAZY);
    char *symbolPtr = toStringz(symbol);
    void *sym = dlsym(main, symbolPtr);
    free(symbolPtr);
    dlclose(main);
    return sym ? true : false;
}

void neat_runtime_dlcall(struct String dlfile, struct String fun, void* arg) {
    void *handle = dlopen(toStringz(dlfile), RTLD_LAZY | RTLD_GLOBAL);
    if (!handle) fprintf(stderr, "can't open %.*s - %s\n", (int) dlfile.length, dlfile.ptr, dlerror());
    assert(!!handle);
    void *sym = dlsym(handle, toStringz(fun));
    if (!sym) fprintf(stderr, "can't load symbol '%.*s'\n", (int) fun.length, fun.ptr);
    assert(!!sym);

    ((void(*)(void*)) sym)(arg);
}

void *neat_runtime_alloc(size_t size) {
    return calloc(1, size);
}

extern void _run_unittests();

#ifndef NEAT_NO_MAIN
extern void MAIN(struct StringArray args);
#endif

int main(int argc, char **argv) {
    struct StringArray args = (struct StringArray) {
        argc,
        malloc(sizeof(struct String) * argc)
    };
    for (int i = 0; i < argc; i++) {
        args.ptr[i] = (struct String) { strlen(argv[i]), argv[i] };
    }
    _run_unittests();
#ifndef NEAT_NO_MAIN
    MAIN(args);
#else
    printf("Unittests run.\n");
#endif
    free(args.ptr);
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

void neat_runtime_refcount_violation(struct String s, ptrdiff_t *ptr)
{
    printf("<%.*s: refcount logic violated: %zd at %p\n", (int) s.length, s.ptr, *ptr, ptr);
    print_backtrace();
}

void neat_runtime_refcount_inc(struct String s, ptrdiff_t *ptr)
{
    // ptrdiff_t result = *ptr += 1;
    ptrdiff_t result = __atomic_add_fetch(ptr, 1, __ATOMIC_ACQ_REL);
    if (result <= 1)
    {
        neat_runtime_refcount_violation(s, ptr);
    }
}

int neat_runtime_refcount_dec(struct String s, ptrdiff_t *ptr)
{
    // ptrdiff_t result = *ptr -= 1;
    ptrdiff_t result = __atomic_sub_fetch(ptr, 1, __ATOMIC_ACQ_REL);
    if (result <= -1)
    {
        neat_runtime_refcount_violation(s, ptr);
    }

    return result == 0;
}

void neat_runtime_class_refcount_inc(void **ptr) {
    if (!ptr) return;
    neat_runtime_refcount_inc((struct String){5, "class", NULL}, (ptrdiff_t*) &ptr[1]);
}

void neat_runtime_class_refcount_dec(void **ptr) {
    if (!ptr) return;
    if (neat_runtime_refcount_dec((struct String){5, "class", NULL}, (ptrdiff_t*) &ptr[1]))
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
    neat_runtime_refcount_inc((struct String){9, "interface", NULL}, (ptrdiff_t*) &object[1]);
}

void neat_runtime_intf_refcount_dec(void *ptr) {
    if (!ptr) return;
    size_t base_offset = **(size_t**) ptr;
    void **object = (void**) ((char*) ptr - base_offset);
    if (neat_runtime_refcount_dec((struct String){9, "interface", NULL}, (ptrdiff_t*) &object[1])) {
        void (**vtable)(void*) = *(void(***)(void*)) object;
        void (*destroy)(void*) = vtable[1];
        destroy(object);
        free(object);
    }
}

void neat_runtime_refcount_set(size_t *ptr, size_t value)
{
    // *ptr = value;
    __atomic_store(ptr, &value, __ATOMIC_RELEASE);
}

int neat_runtime_errno() { return errno; }

pthread_mutex_t stdout_lock;

__attribute__((constructor)) void neat_runtime_stdout_lock_init(void) {
    pthread_mutex_init(&stdout_lock, NULL);
}

void neat_runtime_lock_stdout(void) {
    pthread_mutex_lock(&stdout_lock);
}

void neat_runtime_unlock_stdout(void) {
    pthread_mutex_unlock(&stdout_lock);
}
