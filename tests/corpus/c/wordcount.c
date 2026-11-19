#include <stdio.h>
// ^^^^^ keyword
//       ^^^^^^^^^ string

struct point {
    int x;
    // <- special
    double y;
};

static int area(const struct point *p, int scale) {
    //     ^^^^ definition
    int values[] = {
        1,
        2,
    };
    switch (scale) {
    // ^^^ keyword
    case 1:
        return p->x;
        // ^^^ keyword
    default:
        break;
    }
    if (p == NULL) {
        //   ^^^^ constant
        printf("none %c\n", 'x');
        // ^^^ function
        //     ^^^^^^^^^^^ string
    }
    return values[0] * 3;
    //                 ^ number
}
