#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct String
{
    size_t length;
    char* ptr;
};

struct StringArray
{
    size_t length;
    struct String* ptr;
};

void* ptr_offset(void* p, int i) { return p + i; }
void print(struct String str) { printf("%.*s\n", (int) str.length, str.ptr); }
void assert(int test) { if (!test) abort(); }
int cxruntime_ptr_test(void* ptr) { return !!ptr; }
int _arraycmp(void* a, void* b, size_t la, size_t lb, size_t sz) {
    if (la != lb) return 0;
    return memcmp(a, b, la * sz) == 0;
}
static char* toStringz(struct String str) {
    char *buffer = malloc(str.length + 1);
    strncpy(buffer, str.ptr, str.length);
    buffer[str.length] = 0;
    return buffer;
}
int cxruntime_atoi(struct String str) {
    char *temp = toStringz(str);
    int res = atoi(temp);
    free(temp);
    // printf("atoi(%.*s) = %i\n", str.length, str.ptr, res);
    return res;
}
struct String cxruntime_itoa(int i) {
    int len = snprintf(NULL, 0, "%i", i);
    char *res = malloc(len + 1);
    snprintf(res, len + 1, "%i", i);
    // printf("itoa(%i) = '%.*s'\n", i, len, res);
    return (struct String) { len, res };
}
struct String cxruntime_ltoa(long long l) {
    int len = snprintf(NULL, 0, "%lld", l);
    char *res = malloc(len + 1);
    snprintf(res, len + 1, "%lld", l);
    // printf("ltoa(%lld) = '%.*s'\n", l, len, res);
    return (struct String) { len, res };
}
int cxruntime_linenr(struct String haystack, struct String needle, int* linep, int* columnp) {
    if (needle.ptr < haystack.ptr && needle.ptr >= haystack.ptr + haystack.length)
        return false;
    size_t lineStart = 0, lineEnd, lineNr = 0;
    while (lineStart < haystack.length)
    {
        lineEnd = lineStart;
        while (lineEnd < haystack.length && haystack.ptr[lineEnd] != '\n') lineEnd++;
        struct String line = { lineEnd - lineStart, haystack.ptr + lineStart };

        if (needle.ptr >= line.ptr && needle.ptr <= line.ptr + line.length)
        {
            *linep = (int) lineNr;
            *columnp = (int) (needle.ptr - line.ptr);
            return true;
        }
        lineNr++;
        lineStart = lineEnd + 1;
    }
    abort();
}
int cxruntime_isAlpha(char ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}
int cxruntime_isDigit(char ch) {
    return ch >= '0' && ch <= '9';
}
int cxruntime_file_exists(struct String file) {
    char *fn = toStringz(file);
    int ret = access(fn, F_OK) != -1;
    free(fn);
    return ret;
}
struct String cxruntime_file_read(struct String file) {
    // thanks,
    // https://stackoverflow.com/questions/14002954/c-programming-how-to-read-the-whole-file-contents-into-a-buffer
    char *fn = toStringz(file);
    FILE *f = fopen(fn, "rb");
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);  /* same as rewind(f); */

    char *buffer = malloc(fsize);
    fread(buffer, 1, fsize, f);
    fclose(f);
    free(fn);

    return (struct String) { fsize, buffer };
}

void cxruntime_file_write(struct String file, struct String content) {
    char *fn = toStringz(file);
    FILE *f = fopen(fn, "wb");
    fwrite(content.ptr, 1, content.length, f);
    fclose(f);
    free(fn);
}

void cxruntime_system(struct String command) {
    char *cmd = toStringz(command);
    int ret = system(cmd);
    if (ret != 0) fprintf(stderr, "command failed with %i\n", ret);
    assert(ret == 0);
    free(cmd);
}

void cxruntime_dlcall(struct String dlfile, struct String fun, void* arg) {
    void *handle = dlopen(toStringz(dlfile), RTLD_LAZY);
    if (!handle) fprintf(stderr, "can't open %.*s - %s\n", (int) dlfile.length, dlfile.ptr, dlerror());
    assert(!!handle);
    void *sym = dlsym(handle, toStringz(fun));
    if (!sym) fprintf(stderr, "can't load symbol '%.*s'\n", (int) fun.length, fun.ptr);
    assert(!!sym);

    ((void(*)(void*)) sym)(arg);
}

void *cxruntime_alloc(size_t size) {
    return calloc(1, size);
}

void _main(struct StringArray args);

int main(int argc, char **argv) {
    struct StringArray args = (struct StringArray) {
        argc - 1,
        malloc(sizeof(struct String) * (argc - 1))
    };
    for (int i = 0; i < argc - 1; i = i + 1) {
        args.ptr[i] = (struct String) { strlen(argv[i + 1]), argv[i + 1] };
    }
    _main(args);
    return 0;
}
