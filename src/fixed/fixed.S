# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
/* uint32_t op1_asm(uint32_t a, uint32_t b, int *n)
 * Inputs:
 *   a0 = a
 *   a1 = b
 *   a2 = n (pointer to int)
 * Output:
 *   a0 = result
 */
op1_asm:
    li      t0, 0              /* count = 0 */
    beqz    a1, .Lop1_done
.Lop1_loop:
    and     t1, a0, a1         /* a & b */
    xor     a0, a0, a1         /* a = a ^ b */
    slli    a1, t1, 1          /* b = (a & b) << 1 */
    addi    t0, t0, 1          /* count++ */
    bnez    a1, .Lop1_loop
.Lop1_done:
    beqz    a2, .Lop1_ret      /* if (n) *n = count */
    sw      t0, 0(a2)
.Lop1_ret:
    ret
.size op1_asm, .-op1_asm


.globl op2_asm
.type op2_asm, @function

/* uint32_t op2_asm(uint32_t a, uint32_t b)
 * Inputs: a0 = a, a1 = b
 * Output: a0 = a - b
 */
op2_asm:
    sub     a0, a0, a1
    ret
.size op2_asm, .-op2_asm


.globl op3_asm
.type op3_asm, @function

/* uint32_t op3_asm(uint32_t a, uint32_t b)
 * Formula: (a & b) + ((a ^ b) >> 1)
 * Inputs: a0 = a, a1 = b
 * Output: a0 = floor((a + b) / 2)
 */
op3_asm:
    and     t0, a0, a1         /* t0 = a & b */
    xor     t1, a0, a1         /* t1 = a ^ b */
    srli    t1, t1, 1          /* t1 = (a ^ b) >> 1 */
    add     a0, t0, t1         /* a0 = (a & b) + ((a ^ b) >> 1) */
    ret
.size op3_asm, .-op3_asm


.globl q_mul_asm
.type q_mul_asm, @function

/* int32_t q_mul_asm(int32_t a, int32_t b)
 * Inputs:
 *   a0 = a
 *   a1 = b
 * Output:
 *   a0 = rounded Q11.20 product (low 32 bits)
 */
q_mul_asm:
    /* Unsigned 32x32 -> 64 product of the raw bit patterns, shift-and-add.
     * The smaller (unsigned) operand is the multiplier r, so the loop can
     * stop as soon as r runs out of set bits. The multiplicand m = mh:ml is
     * shifted left as a 64-bit pair. Registers:
     *   t0 = lo, t1 = hi, t2 = r, t3 = mh, t4 = ml, t5/t6 = scratch */
    li      t0, 0
    li      t1, 0
    li      t3, 0
    mv      t2, a1             /* r = b, m = a */
    mv      t4, a0
    bgeu    a0, a1, .Lmul_go
    mv      t2, a0             /* a is smaller: r = a, m = b */
    mv      t4, a1
.Lmul_go:
    beqz    t2, .Lmul_done
.Lmul_step:
    andi    t5, t2, 1
    beqz    t5, .Lmul_shift
    add     t0, t0, t4         /* lo += ml */
    sltu    t6, t0, t4         /* carry */
    add     t1, t1, t3         /* hi += mh */
    add     t1, t1, t6         /*      + carry */
.Lmul_shift:
    srli    t2, t2, 1          /* r >>= 1 */
    srli    t5, t4, 31
    slli    t4, t4, 1          /* m <<= 1 (64-bit) */
    slli    t3, t3, 1
    or      t3, t3, t5
    bnez    t2, .Lmul_step
.Lmul_done:

    /* Signed correction of the high word:
     * hi -= (a < 0 ? b : 0) + (b < 0 ? a : 0) */
    srai    t5, a0, 31
    and     t5, t5, a1
    sub     t1, t1, t5
    srai    t5, a1, 31
    and     t5, t5, a0
    sub     t1, t1, t5

    /* Add 2^19 (half a unit) with carry into hi. */
    lui     t5, 0x80           /* 0x80000 = 2^19 */
    add     t4, t0, t5
    sltu    t6, t4, t0
    add     t1, t1, t6

    /* Result = bits 20..51 = (hi << 12) | (lo >> 20) */
    slli    t1, t1, 12
    srli    t4, t4, 20
    or      a0, t1, t4
    ret
.size q_mul_asm, .-q_mul_asm
