    .text
    .globl  bf16_from_f32_asm
    .globl  bf16_mul_asm
    .globl  bf16_sqrt_asm

/* uint16_t bf16_from_f32_asm(uint32_t f32bits) */
bf16_from_f32_asm:
    lui     t1, 0x7F800         /* exponent mask */
    and     t0, a0, t1
    beq     t0, t1, 1f          /* Inf/NaN: top half unchanged */
    srli    t0, a0, 16
    andi    t0, t0, 1           /* lsb of the kept half */
    lui     t1, 8
    addi    t1, t1, -1          /* 0x7FFF */
    add     a0, a0, t1
    add     a0, a0, t0
1:
    srli    a0, a0, 16
    ret

/* uint16_t bf16_mul_asm(uint16_t a, uint16_t b) */
bf16_mul_asm:
    xor     t0, a0, a1
    srli    t0, t0, 15
    andi    t0, t0, 1
    slli    t0, t0, 15          /* t0 = sign << 15 */
    srli    t1, a0, 7
    andi    t1, t1, 0xFF        /* exp_a */
    srli    t2, a1, 7
    andi    t2, t2, 0xFF        /* exp_b */
    andi    t3, a0, 0x7F        /* mant_a */
    andi    t4, a1, 0x7F        /* mant_b */
    li      t5, 0xFF

    bne     t1, t5, .Lmul_a_finite
    bnez    t3, .Lmul_ret_a     /* NaN a */
    or      t6, t2, t4
    beqz    t6, .Lmul_ret_nan   /* Inf * 0 */
    j       .Lmul_ret_inf
.Lmul_a_finite:
    bne     t2, t5, .Lmul_b_finite
    bnez    t4, .Lmul_ret_b     /* NaN b */
    or      t6, t1, t3
    beqz    t6, .Lmul_ret_nan   /* 0 * Inf */
    j       .Lmul_ret_inf
.Lmul_b_finite:
    or      t6, t1, t3
    beqz    t6, .Lmul_ret_zero
    or      t6, t2, t4
    beqz    t6, .Lmul_ret_zero

    li      a2, 0               /* exp_adjust */
    bnez    t1, .Lmul_a_normal
    li      t1, 1
.Lmul_a_loop:
    andi    t6, t3, 0x80
    bnez    t6, .Lmul_a_done
    slli    t3, t3, 1
    addi    a2, a2, -1
    j       .Lmul_a_loop
.Lmul_a_normal:
    ori     t3, t3, 0x80
.Lmul_a_done:
    bnez    t2, .Lmul_b_normal
    li      t2, 1
.Lmul_b_loop:
    andi    t6, t4, 0x80
    bnez    t6, .Lmul_b_done
    slli    t4, t4, 1
    addi    a2, a2, -1
    j       .Lmul_b_loop
.Lmul_b_normal:
    ori     t4, t4, 0x80
.Lmul_b_done:

    /* a3 = t3 * t4 by shift-and-add */
    li      a3, 0
.Lmul_loop:
    andi    t6, t4, 1
    beqz    t6, 1f
    add     a3, a3, t3
1:
    slli    t3, t3, 1
    srli    t4, t4, 1
    bnez    t4, .Lmul_loop

    add     t1, t1, t2
    add     t1, t1, a2
    addi    t1, t1, -127        /* exp */

    srli    t6, a3, 15
    beqz    t6, .Lmul_shift7
    srli    a3, a3, 8
    addi    t1, t1, 1
    j       .Lmul_normed
.Lmul_shift7:
    srli    a3, a3, 7
.Lmul_normed:
    andi    a3, a3, 0x7F

    bge     t1, t5, .Lmul_ret_inf
    bgtz    t1, .Lmul_pack
    li      t6, -6
    blt     t1, t6, .Lmul_ret_zero
    li      t6, 1
    sub     t6, t6, t1
    srl     a3, a3, t6          /* denormal */
    li      t1, 0
.Lmul_pack:
    slli    t1, t1, 7
    or      a0, t0, t1
    or      a0, a0, a3
    ret
.Lmul_ret_a:
    ret
.Lmul_ret_b:
    mv      a0, a1
    ret
.Lmul_ret_nan:
    lui     a0, 8
    addi    a0, a0, -64         /* 0x7FC0 */
    ret
.Lmul_ret_inf:
    li      t6, 0x7F80
    or      a0, t0, t6
    ret
.Lmul_ret_zero:
    mv      a0, t0
    ret

/* uint16_t bf16_sqrt_asm(uint16_t a) */
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF        /* exp */
    andi    t1, a0, 0x7F        /* mant */
    srli    t2, a0, 15
    andi    t2, t2, 1           /* sign */
    li      t3, 0xFF
    bne     t0, t3, 1f
    bnez    t1, .Lsq_ret        /* NaN */
    bnez    t2, .Lsq_nan        /* -Inf */
    ret                         /* +Inf */
1:
    or      t3, t0, t1
    beqz    t3, .Lsq_zero       /* +0, -0 */
    bnez    t2, .Lsq_nan        /* negative */
    beqz    t0, .Lsq_zero       /* denormal */

    addi    t0, t0, -127        /* e */
    ori     t1, t1, 0x80        /* m */
    andi    t3, t0, 1
    beqz    t3, 2f
    slli    t1, t1, 1
    addi    t0, t0, -1
2:
    srai    t0, t0, 1
    addi    t0, t0, 127         /* new_exp */

    li      a1, 90              /* low */
    li      a2, 256             /* high */
    li      a3, 128             /* result */
.Lsq_loop:
    bgtu    a1, a2, .Lsq_done
    add     a4, a1, a2
    srli    a4, a4, 1           /* mid */
    li      a5, 0               /* a5 = mid * mid */
    mv      t3, a4
    mv      t4, a4
.Lsq_mul:
    andi    t5, t4, 1
    beqz    t5, 3f
    add     a5, a5, t3
3:
    slli    t3, t3, 1
    srli    t4, t4, 1
    bnez    t4, .Lsq_mul
    srli    a5, a5, 7
    bgtu    a5, t1, 4f
    mv      a3, a4
    addi    a1, a4, 1
    j       .Lsq_loop
4:
    addi    a2, a4, -1
    j       .Lsq_loop
.Lsq_done:
    li      t3, 256
    bltu    a3, t3, 5f
    srli    a3, a3, 1
    addi    t0, t0, 1
5:
    li      t3, 0xFF
    bge     t0, t3, .Lsq_inf
    blez    t0, .Lsq_zero
    andi    a3, a3, 0x7F
    slli    t0, t0, 7
    or      a0, t0, a3
.Lsq_ret:
    ret
.Lsq_nan:
    lui     a0, 8
    addi    a0, a0, -64         /* 0x7FC0 */
    ret
.Lsq_inf:
    li      a0, 0x7F80
    ret
.Lsq_zero:
    li      a0, 0
    ret
