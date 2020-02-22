#include "util.h"

#include <stdlib.h>

Data *alloc_data() {
    Data *result = calloc(1, sizeof(Data));
    result->ptr = NULL;
    result->length = 0;
    return result;
}

void free_data(Data *data) {
    free(data->ptr);
    free(data);
}
