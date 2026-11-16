# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# The same four steps as rubik.c, and a subroutine for each helper there:
#
#   check_text     step 1
#   read_cube      step 2
#   QUARTER_TURN   \
#   is_solved       > used by the search (step 3); the two in capitals
#   LOWER_BOUND    /  are macros
#   answer_length  \
#   write_answer    > step 4
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. The tables are in tables.S.
#
# A cube in memory (4 bytes), like cube_t in rubik.c:
#   0: o (halfword)   2: a (byte)   3: b (byte)
#
# The search without recursion
# ----------------------------
# search() in rubik.c calls itself. Here every call gets one "level" in an
# array on the stack instead:
#
#   level[d] (8 bytes):  0..3  the cube of this call
#                        4     last_face
#                        5     face  \ the move this call is trying now,
#                        6     turn  / which is also move d of the answer
#
# A call is made by filling level[d + 1] and moving to it ("go deeper"). A call
# returns 0 by moving back to level[d - 1] ("go back") and trying its next
# move there. When the solved cube is reached, level[0..n-1] hold the answer.
#
# Registers kept during the whole function
#   s0  &level[0]                  s6  twist row = TWIST_TURN[face]
#   s1  &level[d], this call       s7  slot row  = SLOT_TURN[face]
#   s2  n, the length being tried  s8  DIST_OA
#   s3  left                       s9  DIST_AB
#   s4  face                       s10 TIMES210
#   s5  turn                       s11 out
#   a6  TWIST_TURN                 a7  SLOT_TURN

    .equ    B_SOLVED, 108            # b of the solved cube (o and a are 0)
    .equ    FACES, 3
    .equ    NO_FACE, 3
    .equ    TWIST_ROW, 729 * 2       # bytes in one row of TWIST_TURN
    .equ    SLOT_ROW, 210            # bytes in one row of SLOT_TURN

    .equ    LEVEL, 0                 # level[12], 8 bytes each
    .equ    SLOT, 96                 # slot[7], used by read_cube
    .equ    CAP, 104                 # cap
    .equ    SAVE, 108                # ra, s0..s11
    .equ    FRAME, 160

# The two helpers of the search are macros, not subroutines: they run for
# every move tried, and a macro saves the call and the return.

# QUARTER_TURN: the cube at 0(\cube) gets one quarter turn of the face whose
# rows are in s6 (TWIST_TURN[face]) and s7 (SLOT_TURN[face]).
.macro QUARTER_TURN cube
    lhu     t0, 0(\cube)             # o = TWIST_TURN[face][o]
    slli    t0, t0, 1
    add     t0, s6, t0
    lhu     t0, 0(t0)
    sh      t0, 0(\cube)
    lbu     t0, 2(\cube)             # a = SLOT_TURN[face][a]
    add     t0, s7, t0
    lbu     t0, 0(t0)
    sb      t0, 2(\cube)
    lbu     t0, 3(\cube)             # b = SLOT_TURN[face][b]
    add     t0, s7, t0
    lbu     t0, 0(t0)
    sb      t0, 3(\cube)
.endm

# LOWER_BOUND: a0 = lower_bound(the cube at 0(\cube)) = max(need1, need2)
.macro LOWER_BOUND cube
    lhu     t0, 0(\cube)             # o
    lbu     t1, 2(\cube)             # a
    lbu     t2, 3(\cube)             # b

    # need1 = read4(DIST_OA, o * 210 + a)
    slli    t3, t0, 2
    add     t3, s10, t3
    lw      t3, 0(t3)                # o * 210
    add     t3, t3, t1
    srli    t4, t3, 1                # byte = DIST_OA[i / 2]
    add     t4, s8, t4
    lbu     t4, 0(t4)
    andi    t3, t3, 1
    beqz    t3, 1f
    srli    t4, t4, 4                # odd i: high half
1:  andi    t4, t4, 15

    # need2 = read4(DIST_AB, a * 210 + b)
    slli    t3, t1, 2
    add     t3, s10, t3
    lw      t3, 0(t3)                # a * 210
    add     t3, t3, t2
    srli    t5, t3, 1
    add     t5, s9, t5
    lbu     t5, 0(t5)
    andi    t3, t3, 1
    beqz    t3, 2f
    srli    t5, t5, 4
2:  andi    t5, t5, 15

    mv      a0, t4
    bgeu    t4, t5, 3f
    mv      a0, t5
3:
.endm

    .text
    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -FRAME
    sw      ra, SAVE+0(sp)
    sw      s0, SAVE+4(sp)
    sw      s1, SAVE+8(sp)
    sw      s2, SAVE+12(sp)
    sw      s3, SAVE+16(sp)
    sw      s4, SAVE+20(sp)
    sw      s5, SAVE+24(sp)
    sw      s6, SAVE+28(sp)
    sw      s7, SAVE+32(sp)
    sw      s8, SAVE+36(sp)
    sw      s9, SAVE+40(sp)
    sw      s10, SAVE+44(sp)
    sw      s11, SAVE+48(sp)
    mv      s11, a1                  # keep out and cap
    sw      a2, CAP(sp)

    # if (!check_text(state)) return -1;
    mv      s1, a0
    jal     check_text
    beqz    a0, .Linvalid

    # level[0].cube = read_cube(state); level[0].last_face = NO_FACE;
    addi    s0, sp, LEVEL
    mv      a0, s1
    mv      a1, s0
    jal     read_cube
    li      t0, NO_FACE
    sb      t0, 4(s0)

    la      s8, rubik_dist_oa
    la      s9, rubik_dist_ab
    la      s10, rubik_times210
    la      a6, rubik_twist_turn
    la      a7, rubik_slot_turn

# ---- Step 3: search ------------------------------------------------------
    li      s2, 0                    # n = 0, 1, 2, ...
.Ltry_length:
    mv      s1, s0                   # search(start, left = n, NO_FACE)
    mv      s3, s2

    # The two checks at the top of search(), for the first call only:
    # if (left == 0) return is_solved(cube);
    bnez    s3, 1f
    mv      a0, s1
    jal     is_solved
    bnez    a0, .Lfound
    j       .Llonger
    # if (lower_bound(cube) > left) return 0;
1:  LOWER_BOUND s1
    bgtu    a0, s3, .Llonger

.Lcall:                              # one search() call that passed its checks
    # for (face = 0; ...)
    li      s4, 0
    mv      s6, a6                   # rows of face 0
    mv      s7, a7
.Lface_loop:
    li      t0, FACES
    beq     s4, t0, .Lreturn_0       # all faces tried
    lbu     t0, 4(s1)
    beq     s4, t0, .Lnext_face      # face == last_face: skip

    # next = cube;  (next lives in level[d + 1])
    lw      t0, 0(s1)
    sw      t0, 8(s1)
    li      s5, 0                    # turn = 0
.Lturn_loop:
    # next = quarter_turn(next, face);
    addi    a0, s1, 8
    QUARTER_TURN a0
    # remember the move (face, turn)
    sb      s4, 5(s1)
    sb      s5, 6(s1)

    # search(next, left - 1, face) would first do its two checks. Do them
    # here, so a move that fails them never needs a level of its own.
    li      t0, 1
    bne     s3, t0, 2f
    # left - 1 == 0: return is_solved(next)
    addi    a0, s1, 8
    jal     is_solved
    bnez    a0, .Lfound
    j       .Lnext_turn
    # lower_bound(next) > left - 1: return 0
2:  addi    a0, s1, 8
    LOWER_BOUND a0
    addi    t0, s3, -1
    bgtu    a0, t0, .Lnext_turn

    # Both checks passed: go deeper.
    sb      s4, 12(s1)               # level[d + 1].last_face = face
    addi    s1, s1, 8
    addi    s3, s3, -1
    j       .Lcall

.Lreturn_0:                          # this call returns 0
    beq     s1, s0, .Llonger         # it was the first call: n is too short
    addi    s1, s1, -8               # go back to the caller ...
    addi    s3, s3, 1
    lbu     s4, 5(s1)                # ... and its face and turn
    lbu     s5, 6(s1)
    mv      s6, a6                   # rows of that face: face 0 ...
    mv      s7, a7
    beqz    s4, .Lnext_turn
    addi    s6, s6, TWIST_ROW        # ... face 1 ...
    addi    s7, s7, SLOT_ROW
    li      t0, 1
    beq     s4, t0, .Lnext_turn
    addi    s6, s6, TWIST_ROW        # ... face 2
    addi    s7, s7, SLOT_ROW

.Lnext_turn:                         # turn++; still < 3?
    addi    s5, s5, 1
    li      t0, 3
    bne     s5, t0, .Lturn_loop
.Lnext_face:                         # face++
    addi    s4, s4, 1
    addi    s6, s6, TWIST_ROW
    addi    s7, s7, SLOT_ROW
    j       .Lface_loop

.Llonger:                            # try one move more
    addi    s2, s2, 1
    j       .Ltry_length

# ---- Step 4: the answer ----------------------------------------------------
.Lfound:                             # n = s2 moves in level[0..n-1]
    # if (answer_length + 1 > cap) { if (cap > 0) out[0] = 0; return -2; }
    mv      a0, s0
    mv      a1, s2
    jal     answer_length
    lw      t0, CAP(sp)
    bltu    a0, t0, .Lfits           # length < cap means length + 1 <= cap
    li      a0, -2
    beqz    t0, .Lreturn
    sb      zero, 0(s11)
    j       .Lreturn
.Lfits:
    mv      a0, s0
    mv      a1, s2
    mv      a2, s11
    jal     write_answer
    mv      a0, s2                   # return n
    j       .Lreturn

.Linvalid:
    li      a0, -1

.Lreturn:
    lw      ra, SAVE+0(sp)
    lw      s0, SAVE+4(sp)
    lw      s1, SAVE+8(sp)
    lw      s2, SAVE+12(sp)
    lw      s3, SAVE+16(sp)
    lw      s4, SAVE+20(sp)
    lw      s5, SAVE+24(sp)
    lw      s6, SAVE+28(sp)
    lw      s7, SAVE+32(sp)
    lw      s8, SAVE+36(sp)
    lw      s9, SAVE+40(sp)
    lw      s10, SAVE+44(sp)
    lw      s11, SAVE+48(sp)
    addi    sp, sp, FRAME
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm

# ---------------------------------------------------------------------------
# The subroutines. They are only called from rubik_solve_asm, use only the
# t registers and their a registers, and return with ret.
# ---------------------------------------------------------------------------

# check_text: a0 = s  ->  a0 = 1 if valid, 0 if not
check_text:
    # s[0..6]: cubies '1'..'7', each once. Bit c of t0 = cubie c seen.
    li      t0, 0
    li      t1, 0                    # i
.Lcheck_cubie:
    add     t2, a0, t1
    lbu     t2, 0(t2)                # s[i]
    li      t3, '1'
    bltu    t2, t3, .Lbad
    li      t3, '7'
    bgtu    t2, t3, .Lbad
    addi    t2, t2, -'1'             # cubie
    li      t3, 1
    sll     t3, t3, t2               # its bit
    and     t4, t0, t3
    bnez    t4, .Lbad                # seen before
    or      t0, t0, t3
    addi    t1, t1, 1
    li      t3, 7
    bne     t1, t3, .Lcheck_cubie

    # s[7..13]: twists '1'..'3', t0 = their sum
    li      t0, 0
.Lcheck_twist:
    add     t2, a0, t1
    lbu     t2, 0(t2)
    li      t3, '1'
    bltu    t2, t3, .Lbad
    li      t3, '3'
    bgtu    t2, t3, .Lbad
    addi    t2, t2, -'1'
    add     t0, t0, t2               # sum += twist
    addi    t1, t1, 1
    li      t3, 14
    bne     t1, t3, .Lcheck_twist

    # exactly 14 characters
    lbu     t2, 14(a0)
    bnez    t2, .Lbad

    # sum must be 0, 3, 6, ...
    li      t3, 3
.Lcheck_sum:
    bltu    t0, t3, .Lcheck_sum_done
    addi    t0, t0, -3
    j       .Lcheck_sum
.Lcheck_sum_done:
    bnez    t0, .Lbad
    li      a0, 1
    ret
.Lbad:
    li      a0, 0
    ret

# read_cube: a0 = s, a1 = &cube  (writes o, a, b)
# Uses slot[7] in the frame of rubik_solve_asm (sp is not changed).
read_cube:
    # slot[s[i] - '1'] = i  for i = 0..6
    li      t1, 0
.Lread_slot:
    add     t2, a0, t1
    lbu     t2, 0(t2)
    addi    t2, t2, -'1'
    add     t2, sp, t2
    sb      t1, SLOT(t2)
    addi    t1, t1, 1
    li      t3, 7
    bne     t1, t3, .Lread_slot

    # o = s[7..12] as a base-3 number: o = o * 3 + twist
    li      t0, 0
    li      t1, 7
.Lread_twist:
    add     t2, a0, t1
    lbu     t2, 0(t2)
    addi    t2, t2, -'1'
    slli    t3, t0, 1
    add     t0, t0, t3               # o * 3
    add     t0, t0, t2
    addi    t1, t1, 1
    li      t3, 13
    bne     t1, t3, .Lread_twist
    sh      t0, 0(a1)

    # a = SLOT_ID[slot[0]][slot[1]][slot[2]]
    addi    a2, sp, SLOT
    jal     t5, .Lslot_id            # (t5 = return address)
    sb      a0, 2(a1)
    # b = SLOT_ID[slot[3]][slot[4]][slot[5]]
    addi    a2, sp, SLOT+3
    jal     t5, .Lslot_id
    sb      a0, 3(a1)
    ret

# a0 = SLOT_ID[a2[0]][a2[1]][a2[2]], at index a2[0] * 49 + a2[1] * 7 + a2[2]
.Lslot_id:
    lbu     t0, 0(a2)
    slli    t1, t0, 5                # * 32
    slli    t2, t0, 4                # * 16
    add     t1, t1, t2
    add     t1, t1, t0               # * 49
    lbu     t0, 1(a2)
    slli    t2, t0, 3
    sub     t2, t2, t0               # * 7
    add     t1, t1, t2
    lbu     t0, 2(a2)
    add     t1, t1, t0
    la      t2, rubik_slot_id
    add     t1, t2, t1
    lbu     a0, 0(t1)
    jr      t5

# is_solved: a0 = &cube  ->  a0 = 1 if o == 0, a == 0 and b == B_SOLVED
is_solved:
    lhu     t0, 0(a0)
    bnez    t0, 1f
    lbu     t0, 2(a0)
    bnez    t0, 1f
    lbu     t0, 3(a0)
    li      t1, B_SOLVED
    bne     t0, t1, 1f
    li      a0, 1
    ret
1:  li      a0, 0
    ret

# answer_length: a0 = &level[0], a1 = n  ->  a0 = characters without '\0'
answer_length:
    li      t0, 0                    # length
    li      t1, 0                    # i
.Llength_loop:
    beq     t1, a1, .Llength_done
    beqz    t1, 1f
    addi    t0, t0, 1                # the space
1:  addi    t0, t0, 1                # the face letter
    lbu     t2, 6(a0)                # turn
    beqz    t2, 2f
    addi    t0, t0, 1                # '2' or '\''
2:  addi    a0, a0, 8
    addi    t1, t1, 1
    j       .Llength_loop
.Llength_done:
    mv      a0, t0
    ret

# write_answer: a0 = &level[0], a1 = n, a2 = out
write_answer:
    la      t3, .Lface_letter
    la      t4, .Lturn_mark
    li      t1, 0                    # i
.Lwrite_loop:
    beq     t1, a1, .Lwrite_done
    beqz    t1, 1f
    li      t2, ' '
    sb      t2, 0(a2)
    addi    a2, a2, 1
1:  lbu     t2, 5(a0)                # FACE_LETTER[face]
    add     t2, t3, t2
    lbu     t2, 0(t2)
    sb      t2, 0(a2)
    addi    a2, a2, 1
    lbu     t2, 6(a0)                # TURN_MARK[turn], if turn != 0
    beqz    t2, 2f
    add     t2, t4, t2
    lbu     t2, 0(t2)
    sb      t2, 0(a2)
    addi    a2, a2, 1
2:  addi    a0, a0, 8
    addi    t1, t1, 1
    j       .Lwrite_loop
.Lwrite_done:
    sb      zero, 0(a2)
    ret

    .section .rodata
.Lface_letter:
    .ascii  "RBD"
.Lturn_mark:
    .ascii  " 2'"                    # [0] unused
