#include "rubik.h"
#include "tables.h"

/* Optimal solver for the 2x2x2 cube.
 *
 * How it works, in four steps:
 *
 *   1. Check the text: 7 different cubies '1'..'7', then 7 twists '1'..'3'
 *      that add up to a multiple of 3, then the end of the string.
 *
 *   2. Turn the text into a cube_t: three small numbers o, a, b (tables.h
 *      explains them). With these numbers a quarter turn of a face is just
 *      three table lookups.
 *
 *   3. Search. Try every move sequence of length 0, then 1, then 2, ... The
 *      first sequence that solves the cube is a shortest one. Two tricks keep
 *      the search small:
 *        - never turn the same face twice in a row (R then R2 is just R');
 *        - lower_bound() says how many moves a cube needs at least. If that
 *          is more than the moves we have left, stop trying this branch.
 *
 *   4. Write the moves as text: "R2 D B' ...".
 */

#define CUBIES 7
#define FACES 3
#define MAX_MOVES 11 /* no cube needs more than 11 moves */
#define NO_FACE 3    /* "no previous face" at the start of the search */

/* A cube, as three numbers (see tables.h). */
typedef struct {
    unsigned o; /* twists */
    unsigned a; /* slots of cubies 1, 2, 3 */
    unsigned b; /* slots of cubies 4, 5, 6 */
} cube_t;

/* The moves found by the search. Move i is face[i] turned turn[i] + 1 quarter
 * turns: face 0 = R, 1 = B, 2 = D; turn 0 = "R", 1 = "R2", 2 = "R'".
 */
typedef struct {
    int count;
    uint8_t face[MAX_MOVES];
    uint8_t turn[MAX_MOVES];
} moves_t;

/* ---- Step 1: check the text ------------------------------------------ */

/* Returns 1 if s is a valid 14-character state, 0 if not. */
static int check_text(const char *s)
{
    /* s[0..6]: the cubies '1'..'7', each one exactly once. */
    int seen[CUBIES] = {0};
    for (int i = 0; i < 7; i++) {
        if (s[i] < '1' || s[i] > '7')
            return 0; /* also stops at an early '\0' */
        int cubie = s[i] - '1';
        if (seen[cubie])
            return 0; /* the same cubie twice */
        seen[cubie] = 1;
    }

    /* s[7..13]: the twists '1'..'3'. */
    int sum = 0;
    for (int i = 7; i < 14; i++) {
        if (s[i] < '1' || s[i] > '3')
            return 0;
        sum = sum + (s[i] - '1');
    }

    /* Exactly 14 characters. */
    if (s[14] != '\0')
        return 0;

    /* The twists must add up to 0, 3, 6, ... (no % on RV32I: subtract). */
    while (sum >= 3)
        sum = sum - 3;
    if (sum != 0)
        return 0;

    return 1;
}

/* ---- Step 2: text to numbers ----------------------------------------- */

/* s must already have passed check_text(). */
static cube_t read_cube(const char *s)
{
    cube_t cube;

    /* slot[c] = the slot (0..6) that holds cubie c (0..6). */
    int slot[CUBIES];
    for (int i = 0; i < 7; i++)
        slot[s[i] - '1'] = i;

    /* The first six twists, read as one base-3 number. The seventh twist is
     * not needed: it follows from the others.
     */
    cube.o = 0;
    for (int i = 7; i < 13; i++)
        cube.o = cube.o * 3 + (unsigned) (s[i] - '1');

    cube.a = SLOT_ID[slot[0]][slot[1]][slot[2]];
    cube.b = SLOT_ID[slot[3]][slot[4]][slot[5]];
    return cube;
}

/* ---- Helpers for the search ------------------------------------------ */

/* The cube after one quarter turn of `face`. */
static cube_t quarter_turn(cube_t cube, int face)
{
    cube_t next;
    next.o = TWIST_TURN[face][cube.o];
    next.a = SLOT_TURN[face][cube.a];
    next.b = SLOT_TURN[face][cube.b];
    return next;
}

static int is_solved(cube_t cube)
{
    return cube.o == 0 && cube.a == A_SOLVED && cube.b == B_SOLVED;
}

/* Entry i of a table that keeps two 4-bit entries in each byte. */
static unsigned read4(const uint8_t *table, unsigned i)
{
    unsigned byte = table[i / 2];
    if (i % 2 == 0)
        return byte & 15; /* even i: low half */
    else
        return byte >> 4; /* odd i: high half */
}

/* The cube needs at least this many moves. */
static unsigned lower_bound(cube_t cube)
{
    unsigned need1 = read4(DIST_OA, cube.o * 210 + cube.a);
    unsigned need2 = read4(DIST_AB, cube.a * 210 + cube.b);
    if (need1 > need2)
        return need1;
    return need2;
}

/* ---- Step 3: search -------------------------------------------------- */

/* Can `cube` be solved with exactly `left` more moves? The previous move
 * turned `last_face`. On success the moves are appended to `moves`.
 */
static int search(cube_t cube, int left, int last_face, moves_t *moves)
{
    if (left == 0)
        return is_solved(cube);

    if (lower_bound(cube) > (unsigned) left)
        return 0; /* too far away: give up on this branch */

    for (int face = 0; face < FACES; face++) {
        if (face == last_face)
            continue;

        /* turn 0, 1, 2 = one, two, three quarter turns of this face */
        cube_t next = cube;
        for (int turn = 0; turn < 3; turn++) {
            next = quarter_turn(next, face);

            moves->face[moves->count] = (uint8_t) face;
            moves->turn[moves->count] = (uint8_t) turn;
            moves->count++;

            if (search(next, left - 1, face, moves))
                return 1;

            moves->count--; /* did not work: take the move back */
        }
    }
    return 0;
}

/* Fill `moves` with a shortest solution and return its length. */
static int solve(cube_t start, moves_t *moves)
{
    for (int n = 0; n <= MAX_MOVES; n++) {
        moves->count = 0;
        if (search(start, n, NO_FACE, moves))
            return n;
    }
    return -1; /* never happens: every cube is solved in 11 moves */
}

/* ---- Step 4: the answer as text -------------------------------------- */

/* Characters of the answer, without the final '\0'. */
static unsigned answer_length(const moves_t *moves)
{
    unsigned length = 0;
    for (int i = 0; i < moves->count; i++) {
        if (i > 0)
            length = length + 1; /* the space before the move */
        length = length + 1;     /* the face letter */
        if (moves->turn[i] != 0)
            length = length + 1; /* the '2' or '\'' */
    }
    return length;
}

static void write_answer(const moves_t *moves, char *out)
{
    static const char FACE_LETTER[FACES] = {'R', 'B', 'D'};
    static const char TURN_MARK[3] = {0, '2', '\''};

    int pos = 0;
    for (int i = 0; i < moves->count; i++) {
        if (i > 0)
            out[pos++] = ' ';
        out[pos++] = FACE_LETTER[moves->face[i]];
        if (moves->turn[i] != 0)
            out[pos++] = TURN_MARK[moves->turn[i]];
    }
    out[pos] = '\0';
}

/* ---- The whole solver ------------------------------------------------ */

int rubik_solve(const char *state, char *out, size_t cap)
{
    if (!check_text(state))
        return -1;

    cube_t start = read_cube(state);

    moves_t moves;
    int n = solve(start, &moves);

    /* The text and its '\0' must fit in cap bytes. */
    if (answer_length(&moves) + 1 > cap) {
        if (cap > 0)
            out[0] = '\0';
        return -2;
    }
    write_answer(&moves, out);
    return n;
}
