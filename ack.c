#include <stdio.h>
#include <stdlib.h>

int ack(int m, int n) {
    if (m == 0) return n + 1;
    if (n == 0) return ack(m - 1, 1);
    return ack(m - 1, ack(m, n - 1));
}

int main(int argc, char **argv) {
    int m = atoi(argv[1]), n = atoi(argv[2]);
    for (int i = 0; i < 10; i++) {
        printf("ack(%i, %i) = %i\n", m, n, ack(m, n));
    }
    return 0;
}
