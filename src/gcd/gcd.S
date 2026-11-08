
# gcd_u32_asm: binary GCD
#
#   a0 = a      (also the return value)
#   a1 = b
#   t0 = k      (number of common factors of 2)
#   t1, t2      temporaries

    .text
    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    # if (a == 0) return b;
    beqz    a0, .Lreturn_b
    # if (b == 0) return a;
    beqz    a1, .Lreturn_a

    # k = 0;
    li      t0, 0

    # while (((a | b) & 1) == 0) { a >>= 1; b >>= 1; k++; }
.Lremove_common_2:
    or      t1, a0, a1          # t1 = a | b
    andi    t1, t1, 1           # t1 = (a | b) & 1
    bnez    t1, .Lmake_a_odd    # odd -> loop ends
    srli    a0, a0, 1           # a >>= 1
    srli    a1, a1, 1           # b >>= 1
    addi    t0, t0, 1           # k++
    j       .Lremove_common_2

    # while ((a & 1) == 0) a >>= 1;
.Lmake_a_odd:
    andi    t1, a0, 1
    bnez    t1, .Lloop
    srli    a0, a0, 1
    j       .Lmake_a_odd

.Lloop:
    andi    t1, a1, 1
    bnez    t1, .Lcompare

    # while ((b & 1) == 0) b >>= 1;
    
.Lmake_b_odd:
    srli    a1, a1, 1           # b >>= 1
    andi    t1, a1, 1
    beqz    t1, .Lmake_b_odd   

    # do { ... } while (b != 0);   a and b are both odd here
.Lcompare:
    bgeu    a1, a0, .Lsubtract  # b >= a -> no swap

    # a > b: swap and subtract in one step
    #   new a = old b,  new b = old a - old b
    sub     t2, a0, a1          # t2 = a - b
    mv      a0, a1              # a = b
    mv      a1, t2              # b = a - b
    j       .Lmake_b_odd        # (a - b) is even and nonzero

    # b = b - a;
.Lsubtract:
    sub     a1, a1, a0
    bnez    a1, .Lmake_b_odd    # } while (b != 0);

    # return a << k;
    sll     a0, a0, t0
    ret

.Lreturn_b:
    mv      a0, a1              # return b
.Lreturn_a:
    ret                         # return a (already in a0)

    .size   gcd_u32_asm, .-gcd_u32_asm

