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

BytecodeBuilder *alloc_bc_builder()
{
    BytecodeBuilder *result = calloc(1, sizeof(BytecodeBuilder));
    result->data = alloc_data();
    result->symbol_offsets_len = 0;
    result->symbol_offsets_ptr = NULL;
    return result;
}

void free_bc_builder(BytecodeBuilder *builder)
{
    free_data(builder->data);
    free(builder);
}
