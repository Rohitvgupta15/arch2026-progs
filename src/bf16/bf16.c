#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f)
{
    /* Inf and NaN: keep the top half unchanged. */
    if (((f >> 23) & 0xFF) == 0xFF)
        return (uint16_t) (f >> 16);

    /* Round to nearest, ties to even. */
    f += 0x7FFF + ((f >> 16) & 1);
    return (uint16_t) (f >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = ((a ^ b) >> 15) & 1;
    int32_t exp_a = (a >> 7) & 0xFF;
    int32_t exp_b = (b >> 7) & 0xFF;
    uint32_t mant_a = a & 0x7F;
    uint32_t mant_b = b & 0x7F;

    /* a is examined first, then b. */
    if (exp_a == 0xFF) {
        if (mant_a)
            return a; /* NaN */
        if (!exp_b && !mant_b)
            return 0x7FC0; /* Inf * 0 */
        return (uint16_t) ((sign << 15) | 0x7F80);
    }
    if (exp_b == 0xFF) {
        if (mant_b)
            return b; /* NaN */
        if (!exp_a && !mant_a)
            return 0x7FC0; /* 0 * Inf */
        return (uint16_t) ((sign << 15) | 0x7F80);
    }

    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return (uint16_t) (sign << 15);

    /* Normalize denormals, add the hidden one to normals. */
    int32_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else {
        mant_a |= 0x80;
    }
    if (!exp_b) {
        while (!(mant_b & 0x80)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else {
        mant_b |= 0x80;
    }

    uint32_t mant = mant_a * mant_b;
    int32_t exp = exp_a + exp_b - 127 + exp_adjust;

    /* Renormalize and truncate. */
    if (mant & 0x8000) {
        mant = (mant >> 8) & 0x7F;
        exp++;
    } else {
        mant = (mant >> 7) & 0x7F;
    }

    if (exp >= 0xFF)
        return (uint16_t) ((sign << 15) | 0x7F80);
    if (exp <= 0) {
        if (exp < -6)
            return (uint16_t) (sign << 15);
        mant >>= (1 - exp);
        exp = 0;
    }
    return (uint16_t) ((sign << 15) | ((uint32_t) exp << 7) | mant);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t sign = (a >> 15) & 1;
    int32_t exp = (a >> 7) & 0xFF;
    uint32_t mant = a & 0x7F;

    if (exp == 0xFF) {
        if (mant)
            return a; /* NaN */
        if (sign)
            return 0x7FC0; /* sqrt(-Inf) */
        return a;          /* sqrt(+Inf) */
    }
    if (!exp && !mant)
        return 0; /* +0 and -0 give +0 */
    if (sign)
        return 0x7FC0;
    if (!exp)
        return 0; /* denormals */

    int32_t e = exp - 127;
    uint32_t m = 0x80 | mant;
    if (e & 1) {
        m <<= 1;
        e--;
    }
    int32_t new_exp = (e >> 1) + 127;

    /* Largest mid in [90, 256] with (mid * mid) / 128 <= m. */
    uint32_t low = 90, high = 256, result = 128;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) >> 7;
        if (sq <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    if (result >= 256) {
        result >>= 1;
        new_exp++;
    }

    if (new_exp >= 0xFF)
        return 0x7F80;
    if (new_exp <= 0)
        return 0;
    return (uint16_t) (((uint32_t) new_exp << 7) | (result & 0x7F));
}
