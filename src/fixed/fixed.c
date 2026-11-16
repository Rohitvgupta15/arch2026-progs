#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int count = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        count++;
    }
    if (n) {
        *n = count;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    /*
     * Unsigned 32x32 -> 64 product by shift-and-add. The multiplier starts in
     * lo; each pass tests its low bit, adds the multiplicand into hi, then
     * shifts the 65-bit (carry:hi:lo) right by one. After 32 passes hi:lo is
     * the full product.
     */
    uint32_t ua = (uint32_t) a;
    uint32_t hi = 0;
    uint32_t lo = (uint32_t) b;

    for (int i = 0; i < 32; i++) {
        uint32_t carry = 0;
        if (lo & 1) {
            hi += ua;
            carry = hi < ua;
        }
        lo = (lo >> 1) | (hi << 31);
        hi = (hi >> 1) | (carry << 31);
    }

    /*
     * Signed correction: the low word of the signed and unsigned products is
     * the same; the signed high word is the unsigned one minus b if a < 0 and
     * minus a if b < 0.
     */
    if (a < 0)
        hi -= (uint32_t) b;
    if (b < 0)
        hi -= (uint32_t) a;

    /* Add half a unit (2^19) with carry into hi. */
    uint32_t next_lo = lo + (1u << (Q - 1));
    hi += next_lo < lo;
    lo = next_lo;

    /* Bits 20..51 of the 64-bit sum. */
    return (int32_t) ((hi << (32 - Q)) | (lo >> Q));
}
