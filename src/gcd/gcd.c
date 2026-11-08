#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    // Handle the trivial cases first
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    unsigned k = 0;
    // Remove all common factors of 2 from a and b, keeping track of how many
    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        k++;
    }
    // Remove all factors of 2 from a, leaving b odd
    while ((a & 1u) == 0)
        a >>= 1;
    // Now a is odd, and b is odd or even. The loop below will keep b odd, an
    do {
        while ((b & 1u) == 0)
            b >>= 1;

        if (a > b) {  // swap a and b so that a <= b
            uint32_t t = a;
            a = b;
            b = t;
        }

        b = b - a;  // b is now even, so the next iteration will remove all
                    // factors of 2 from it

    } while (b != 0);

    return a << k;  // multiply by 2^k
}
