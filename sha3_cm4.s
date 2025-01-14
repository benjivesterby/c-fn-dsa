	.syntax	unified
	.cpu	cortex-m4
	.file	"sha3_cm4.s"
	.text

@ =======================================================================
@ void fndsa_sha3_inject_chunk(void *dst, const void *src, size_t len)
@ =======================================================================

	.align	2
	.global	fndsa_sha3_inject_chunk
	.thumb
	.thumb_func
	.type	fndsa_sha3_inject_chunk, %function
fndsa_sha3_inject_chunk:
	push	{ r4, r5 }

	@ If less than 8 bytes to inject, do it byte-by-byte.
	cmp	r2, #8
	blo	fndsa_sha3_inject_chunk__L4

	@ Process some bytes until the destination is aligned.
	rsbs	r5, r0, #0
	ands	r5, #3
	beq	fndsa_sha3_inject_chunk__L2
	subs	r2, r5
fndsa_sha3_inject_chunk__L1:
	ldrb	r3, [r0]
	ldrb	r4, [r1], #1
	eors	r3, r4
	strb	r3, [r0], #1
	subs	r5, #1
	bne	fndsa_sha3_inject_chunk__L1

fndsa_sha3_inject_chunk__L2:
	@ Destination is aligned. Source might be unaligned, but the
	@ Cortex-M4 tolerates unaligns accesses with a penalty which is
	@ lower than doing word reassembly in software.
	lsrs	r5, r2, #2
fndsa_sha3_inject_chunk__L3:
	ldr	r3, [r0]
	ldr	r4, [r1], #4
	eors	r3, r4
	str	r3, [r0], #4
	subs	r5, #1
	bne	fndsa_sha3_inject_chunk__L3

	@ We may have a remaining tail of up to 3 bytes.
	ands	r2, #3
	beq	fndsa_sha3_inject_chunk__L5

fndsa_sha3_inject_chunk__L4:
	@ Byte-by-byte processing for the data tail.
	ldrb	r3, [r0]
	ldrb	r4, [r1], #1
	eors	r3, r4
	strb	r3, [r0], #1
	subs	r2, #1
	bne	fndsa_sha3_inject_chunk__L4

fndsa_sha3_inject_chunk__L5:
	pop	{ r4, r5 }
	bx	lr
	.size	fndsa_sha3_inject_chunk,.-fndsa_sha3_inject_chunk

@ =======================================================================
@ void fndsa_sha3_process_block(uint64_t *A)
@ =======================================================================

	.align	2
	.global	fndsa_sha3_process_block
	.thumb
	.thumb_func
	.type	fndsa_sha3_process_block, %function
fndsa_sha3_process_block:
	push	{ r4, r5, r6, r7, r8, r10, r11, lr }
	vmov	r1, s16
	push	{ r1 }
	sub	sp, sp, #200

	@ Conventions:
	@  - We cache five state values in the FP registers:
	@    A[4]    s0, s1
	@    A[9]    s2, s3
	@    A[14]   s4, s5
	@    A[19]   s6, s7
	@    A[24]   s8, s9
	@  - s10 to s15 are temporaries
	@  - loop counter (multiplied by 8) if kept in s16
	@ We use a 200-byte stack buffer for intermediate values.

	@ Invert some words (alternate internal representation, which
	@ saves some operations).
.macro	INVERT_WORDS
	@ Invert A[1] and A[2].
	add	r1, r0, #8
	ldm	r1, { r2, r3, r4, r5 }
	mvns	r2, r2
	mvns	r3, r3
	mvns	r4, r4
	mvns	r5, r5
	stm	r1!, { r2, r3, r4, r5 }
	@ Invert A[8]
	adds	r1, r0, #64
	ldm	r1, { r2, r3 }
	mvns	r2, r2
	mvns	r3, r3
	stm	r1!, { r2, r3 }
	@ Invert A[12]
	adds	r1, r0, #96
	ldm	r1, { r2, r3 }
	mvns	r2, r2
	mvns	r3, r3
	stm	r1!, { r2, r3 }
	@ Invert A[17]
	adds	r1, r0, #136
	ldm	r1, { r2, r3 }
	mvns	r2, r2
	mvns	r3, r3
	stm	r1!, { r2, r3 }
	@ Invert A[20]
	adds	r1, r0, #160
	ldm	r1, { r2, r3 }
	mvns	r2, r2
	mvns	r3, r3
	stm	r1!, { r2, r3 }
.endm

	INVERT_WORDS

	@ Load some values into FP registers.
	ldrd	r2, r3, [r0, #32]
	vmov	s0, s1, r2, r3
	ldrd	r2, r3, [r0, #72]
	vmov	s2, s3, r2, r3
	ldrd	r2, r3, [r0, #112]
	vmov	s4, s5, r2, r3
	ldrd	r2, r3, [r0, #152]
	vmov	s6, s7, r2, r3
	ldrd	r2, r3, [r0, #192]
	vmov	s8, s9, r2, r3

	@ Do 24 rounds. Each loop iteration performs one round. We
	@ keep eight times the current round counter in s16 (i.e.
	@ a multiple of 8, from 0 to 184).

	eors	r1, r1
	vmov	s16, r1

	@ Inside the main loop, we take care to keep 32-bit alignment;
	@ this appears to help the CPU: on an STM32F407 microcontroller,
	@ the cost of this function is reduced by a few hundred cycles
	@ when we do that. This may be due to an interaction between the
	@ instruction fetch unit and the write buffer, and it might involve
	@ the out-of-core interconnection matrix (i.e. it might plausibly
	@ work differently on other microcontrollers that use the same
	@ ARM Cortex M4 core).
	b	process_block_loop
	.align	2
process_block_loop:
	@ xor(A[5*i+0]) -> r1:r2
	@ xor(A[5*i+1]) -> r3:r4
	@ xor(A[5*i+2]) -> r5:r6
	@ xor(A[5*i+3]) -> r7:r8
	@ xor(A[5*i+4]) -> r10:r11
	@ Values 5*i+4 are in FP registers
	ldm	r0!, { r1, r2, r3, r4, r5, r6, r7, r8 }
	add.w	r0, r0, #8
	ldm	r0!, { r10, r11, r12 }
	eor	r1, r1, r10
	eor	r2, r2, r11
	eor	r3, r3, r12
	ldm	r0!, { r10, r11, r12 }
	eor	r4, r4, r10
	eor	r5, r5, r11
	eor	r6, r6, r12
	ldm	r0!, { r10, r11 }
	eor	r7, r7, r10
	eor	r8, r8, r11
	add.w	r0, r0, #8
	ldm	r0!, { r10, r11, r12 }
	eor	r1, r1, r10
	eor	r2, r2, r11
	eor	r3, r3, r12
	ldm	r0!, { r10, r11, r12 }
	eor	r4, r4, r10
	eor	r5, r5, r11
	eor	r6, r6, r12
	ldm	r0!, { r10, r11 }
	eor	r7, r7, r10
	eor	r8, r8, r11
	add.w	r0, r0, #8
	ldm	r0!, { r10, r11, r12 }
	eor	r1, r1, r10
	eor	r2, r2, r11
	eor	r3, r3, r12
	ldm	r0!, { r10, r11, r12 }
	eor	r4, r4, r10
	eor	r5, r5, r11
	eor	r6, r6, r12
	ldm	r0!, { r10, r11 }
	eor	r7, r7, r10
	eor	r8, r8, r11
	add.w	r0, r0, #8
	ldm	r0!, { r10, r11, r12 }
	eor	r1, r1, r10
	eor	r2, r2, r11
	eor	r3, r3, r12
	ldm	r0!, { r10, r11, r12 }
	eor	r4, r4, r10
	eor	r5, r5, r11
	eor	r6, r6, r12
	ldm	r0!, { r10, r11 }
	eor	r7, r7, r10
	eor	r8, r8, r11

	sub.w	r0, r0, #192
	vmov	r10, r11, s0, s1
	vmov	r12, s2
	eor	r10, r10, r12
	vmov	r12, s3
	eor	r11, r11, r12
	vmov	r12, s4
	eor	r10, r10, r12
	vmov	r12, s5
	eor	r11, r11, r12
	vmov	r12, s6
	eor	r10, r10, r12
	vmov	r12, s7
	eor	r11, r11, r12
	vmov	r12, s8
	eor	r10, r10, r12
	vmov	r12, s9
	eor	r11, r11, r12

	@ t0 = xor(A[5*i+4]) ^ rotl1(xor(A[5*i+1])) -> r10:r11
	@ t1 = xor(A[5*i+0]) ^ rotl1(xor(A[5*i+2])) -> r1:r2
	@ t2 = xor(A[5*i+1]) ^ rotl1(xor(A[5*i+3])) -> r3:r4
	@ t3 = xor(A[5*i+2]) ^ rotl1(xor(A[5*i+4])) -> r5:r6
	@ t4 = xor(A[5*i+3]) ^ rotl1(xor(A[5*i+0])) -> r7:r8
	vmov	s10, r11
	mov.w	r12, r10
	eor	r10, r10, r3, lsl #1
	eor	r10, r10, r4, lsr #31
	eor	r11, r11, r4, lsl #1
	eor	r11, r11, r3, lsr #31
	eor	r3, r3, r7, lsl #1
	eor	r3, r3, r8, lsr #31
	eor	r4, r4, r8, lsl #1
	eor	r4, r4, r7, lsr #31
	eor	r7, r7, r1, lsl #1
	eor	r7, r7, r2, lsr #31
	eor	r8, r8, r2, lsl #1
	eor	r8, r8, r1, lsr #31
	eor	r1, r1, r5, lsl #1
	eor	r1, r1, r6, lsr #31
	eor	r2, r2, r6, lsl #1
	eor	r2, r2, r5, lsr #31
	eor	r5, r5, r12, lsl #1
	eor	r6, r6, r12, lsr #31
	vmov	r12, s10
	eor	r5, r5, r12, lsr #31
	eor	r6, r6, r12, lsl #1

	@ Save t2, t3 and t4 into FP registers.
	vmov	s10, s11, r3, r4
	vmov	s12, s13, r5, r6
	vmov	s14, s15, r7, r8

	@ We XOR one of the t0..t4 values into each A[] word, and
	@ rotate the result by some amount (each word has its own
	@ amount). The results are written back into a stack buffer
	@ that starts at sp
	mov.w	r12, sp

	@ x0:x1 <- rotl(x0:x1 ^ t0:x1, n)
	@ state[r12 ++] <- x0:x1
.macro	ST_XOR_ROT  x0, x1, t0, t1, u0, u1, n
	.if (\n) == 0
	eor	\x0, \x0, \t0
	str	\x0, [r12], #4
	eor	\x1, \x1, \t1
	str	\x1, [r12], #4
	.elseif (\n) < 32
	eor	\u0, \x0, \t0
	eor	\u1, \x1, \t1
	lsl	\x0, \u0, (\n)
	orr	\x0, \x0, \u1, lsr #(32 - (\n))
	str	\x0, [r12], #4
	lsl	\x1, \u1, (\n)
	orr	\x1, \x1, \u0, lsr #(32 - (\n))
	str	\x1, [r12], #4
	.elseif (\n) == 32
	eor	\u0, \x0, \t0
	eor	\x0, \x1, \t1
	str	\x0, [r12], #4
	mov.w	\x1, \u0
	str	\x1, [r12], #4
	.else
	eor	\u0, \x0, \t0
	eor	\u1, \x1, \t1
	lsl	\x0, \u1, ((\n) - 32)
	orr	\x0, \x0, \u0, lsr #(64 - (\n))
	str	\x0, [r12], #4
	lsl	\x1, \u0, ((\n) - 32)
	orr	\x1, \x1, \u1, lsr #(64 - (\n))
	str	\x1, [r12], #4
	.endif
.endm

	@ x0:x1 <- rotl_partial(x0:x1 ^ t0:x1, n)
	@ state[r12 ++] <- x0:x1
	@ Rotation is partial: each word must be rotated again (by itself).
.macro	ST_XOR_ROT_PARTIAL  x0, x1, t0, t1, u0, u1, n
	.if (\n) == 0
	eor	\x0, \x0, \t0
	str	\x0, [r12], #4
	eor	\x1, \x1, \t1
	str	\x1, [r12], #4
	.elseif (\n) < 32
	eor	\u0, \x1, \t1
	eor	\x1, \x0, \t0
	mov.w	\x0, \u0
	bfi	\x0, \x1, #0, #(32 - (\n))
	str	\x0, [r12], #4
	bfi	\x1, \u0, #0, #(32 - (\n))
	str	\x1, [r12], #4
	.elseif (\n) == 32
	eor	\u0, \x0, \t0
	eor	\x0, \x1, \t1
	str	\x0, [r12], #4
	mov.w	\x1, \u0
	str	\x1, [r12], #4
	.else
	eor	\x0, \x0, \t0
	eor	\x1, \x1, \t1
	mov.w	\u0, \x0
	bfi	\x0, \x1, #0, #(64 - (\n))
	str	\x0, [r12], #4
	bfi	\x1, \u0, #0, #(64 - (\n))
	str	\x1, [r12], #4
	.endif
.endm

	@ XOR t0 into A[5*i+0] and t1 into A[5*i+1]; each A[i] is also
	@ rotated left by some amount.
	@ Some words use only the "partial" rotation, which is 1 cycle
	@ shorter, but requires some extra rotations to be smuggled into
	@ the KHI_STEP* macros.

	@ A[0] and A[1]
	ldm	r0!, { r5, r6, r7, r8 }
	eor	r5, r5, r10
	eor	r6, r6, r11
	eor	r3, r7, r1
	eor	r4, r8, r2
	adds.w	r7, r3, r3
	adcs	r8, r4, r4
	adcs	r7, r7, #0
	stm	r12!, { r5, r6, r7, r8 }

	@ A[5] and A[6]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT  r5, r6, r10, r11, r3, r4, 36
	ST_XOR_ROT  r7, r8, r1, r2, r3, r4, 44

	@ A[10] and A[11]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT_PARTIAL  r5, r6, r10, r11, r3, r4, 3
	ST_XOR_ROT_PARTIAL  r7, r8, r1, r2, r3, r4, 10

	@ A[15] and A[16]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT  r5, r6, r10, r11, r3, r4, 41
	ST_XOR_ROT  r7, r8, r1, r2, r3, r4, 45

	@ A[20] and A[21]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT  r5, r6, r10, r11, r3, r4, 18
	ST_XOR_ROT_PARTIAL  r7, r8, r1, r2, r3, r4, 2

	@ XOR t2 into A[5*i+2] and t3 into A[5*i+3]; each A[i] is also
	@ rotated left by some amount. We reload t2 into r1:r2 and t3
	@ into r3:r4.
	vmov	r1, r2, s10, s11
	vmov	r3, r4, s12, s13

	@ A[2] and A[3]
	sub.w	r0, r0, #160
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT  r5, r6, r1, r2, r10, r11, 62
	ST_XOR_ROT  r7, r8, r3, r4, r10, r11, 28

	@ A[7] and A[8]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT  r5, r6, r1, r2, r10, r11, 6
	ST_XOR_ROT_PARTIAL  r7, r8, r3, r4, r10, r11, 55

	@ A[12] and A[13]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT_PARTIAL  r5, r6, r1, r2, r10, r11, 43
	ST_XOR_ROT_PARTIAL  r7, r8, r3, r4, r10, r11, 25

	@ A[17] and A[18]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT  r5, r6, r1, r2, r10, r11, 15
	ST_XOR_ROT  r7, r8, r3, r4, r10, r11, 21

	@ A[22] and A[23]
	add.w	r0, r0, #24
	ldm	r0!, { r5, r6, r7, r8 }
	ST_XOR_ROT_PARTIAL  r5, r6, r1, r2, r10, r11, 61
	ST_XOR_ROT  r7, r8, r3, r4, r10, r11, 56

	@ XOR t4 into A[5*i+4]; each A[i] is also rotated left by some
	@ amount. We reload t4 into r1:r2.
	vmov	r1, r2, s14, s15

	@ A[4]
	vmov	r5, r6, s0, s1
	ST_XOR_ROT  r5, r6, r1, r2, r3, r4, 27

	@ A[9]
	vmov	r5, r6, s2, s3
	ST_XOR_ROT  r5, r6, r1, r2, r3, r4, 20

	@ A[14]
	vmov	r5, r6, s4, s5
	ST_XOR_ROT  r5, r6, r1, r2, r3, r4, 39

	@ A[19]
	vmov	r5, r6, s6, s7
	ST_XOR_ROT  r5, r6, r1, r2, r3, r4, 8

	@ A[24]
	vmov	r5, r6, s8, s9
	ST_XOR_ROT_PARTIAL  r5, r6, r1, r2, r3, r4, 14

	@ Restore r0 to the address of A[0].
	sub.w	r0, r0, #192

	@ At that point, the stack buffer at sp contains the words
	@ at the following indexes (0 to 24) and unfinished left-rotation
	@ count (A[i] is at address sp+8*i):
	@   A[ 0]    0
	@   A[ 1]    1
	@   A[ 2]   10
	@   A[ 3]   11
	@   A[ 4]   20
	@   A[ 5]    2
	@   A[ 6]    3
	@   A[ 7]   12
	@   A[ 8]   13     55
	@   A[ 9]   21
	@   A[10]    4      3
	@   A[11]    5     10
	@   A[12]   14     43
	@   A[13]   15     25
	@   A[14]   22     14
	@   A[15]    6
	@   A[16]    7
	@   A[17]   16
	@   A[18]   17
	@   A[19]   23
	@   A[20]    8
	@   A[21]    9      2
	@   A[22]   18     61
	@   A[23]   19
	@   A[24]   24

.macro	KHI_LOAD  k0, k1, k2, k3, k4
	@ We use ldr and not ldrd because it allows the CPU to pair them;
	@ the whole sequence of 10 reads then executes in 11 cycles.
	ldr	r1, [sp, #(8 * (\k0))]
	ldr	r2, [sp, #(4 + 8 * (\k0))]
	ldr	r3, [sp, #(8 * (\k1))]
	ldr	r4, [sp, #(4 + 8 * (\k1))]
	ldr	r5, [sp, #(8 * (\k2))]
	ldr	r6, [sp, #(4 + 8 * (\k2))]
	ldr.w	r7, [sp, #(8 * (\k3))]
	ldr	r8, [sp, #(4 + 8 * (\k3))]
	ldr	r10, [sp, #(8 * (\k4))]
	ldr	r11, [sp, #(4 + 8 * (\k4))]
.endm

.macro KHI_STEP_CORE  op, x0, x1, x2, x3, ls1, x4, x5, ls2, d
	\op	r12, \x0, \x2, ror #((64 - (\ls1)) % 32)
	eor	r12, r12, \x4, ror #((64 - (\ls2)) % 32)
	.if (\d) == 4
	vmov	s0, r12
	.elseif (\d) == 9
	vmov	s2, r12
	.elseif (\d) == 14
	vmov	s4, r12
	.elseif (\d) == 19
	vmov	s6, r12
	.elseif (\d) == 24
	vmov	s8, r12
	.else
	str	r12, [r0, #(8 * (\d))]
	.endif
	\op	r12, \x1, \x3, ror #((64 - (\ls1)) % 32)
	eor	r12, r12, \x5, ror #((64 - (\ls2)) % 32)
	.if (\d) == 4
	vmov	s1, r12
	.elseif (\d) == 9
	vmov	s3, r12
	.elseif (\d) == 14
	vmov	s5, r12
	.elseif (\d) == 19
	vmov	s7, r12
	.elseif (\d) == 24
	vmov	s9, r12
	.else
	str	r12, [r0, #(4 + 8 * (\d))]
	.endif
.endm

.macro KHI_STEP_R1  op, x0, x1, x2, x3, ls1, x4, x5, d
	KHI_STEP_CORE  \op, \x0, \x1, \x2, \x3, \ls1, \x4, \x5, 0, \d
.endm

.macro KHI_STEP_R2  op, x0, x1, x2, x3, x4, x5, ls2, d
	KHI_STEP_CORE  \op, \x0, \x1, \x2, \x3, 0, \x4, \x5, \ls2, \d
.endm

.macro KHI_STEP_R1R2  op, x0, x1, x2, x3, ls1, x4, x5, ls2, d
	KHI_STEP_CORE  \op, \x0, \x1, \x2, \x3, \ls1, \x4, \x5, \ls2, \d
.endm

.macro KHI_STEP  op, x0, x1, x2, x3, x4, x5, d
	KHI_STEP_CORE  \op, \x0, \x1, \x2, \x3, 0, \x4, \x5, 0, \d
.endm

	@ A[0], A[6], A[12], A[18] and A[24]
	KHI_LOAD  0, 3, 14, 17, 24
	KHI_STEP_R1    orrs, r3, r4, r5, r6, 43, r1, r2, 0
	KHI_STEP_R1    orns, r7, r8, r5, r6, 43, r3, r4, 1
	KHI_STEP_R1R2  ands, r7, r8, r10, r11, 14, r5, r6, 43, 2
	KHI_STEP_R1    orrs, r1, r2, r10, r11, 14, r7, r8, 3
	KHI_STEP_R2    ands, r1, r2, r3, r4, r10, r11, 14, 4

	@ A[3], A[9], A[10], A[16] and A[22]
	KHI_LOAD  11, 21, 4, 7, 18
	KHI_STEP_R1    orrs, r3, r4, r5, r6, 3, r1, r2, 5
	KHI_STEP_R1    ands, r7, r8, r5, r6, 3, r3, r4, 6
	KHI_STEP_R1R2  orns, r7, r8, r10, r11, 61, r5, r6, 3, 7
	KHI_STEP_R1    orrs, r1, r2, r10, r11, 61, r7, r8, 8
	KHI_STEP_R2    ands, r1, r2, r3, r4, r10, r11, 61, 9

	@ A[1], A[7], A[13], A[19] and A[20]
	KHI_LOAD  1, 12, 15, 23, 8
	KHI_STEP_R1    orrs, r3, r4, r5, r6, 25, r1, r2, 10
	KHI_STEP_R1    ands, r7, r8, r5, r6, 25, r3, r4, 11
	KHI_STEP_R2    bics, r10, r11, r7, r8, r5, r6, 25, 12
	mvn.w	r7, r7
	mvn	r8, r8
	KHI_STEP       orrs, r1, r2, r10, r11, r7, r8, 13
	KHI_STEP       ands, r1, r2, r3, r4, r10, r11, 14

	@ A[4], A[5], A[11], A[17] and A[23]
	KHI_LOAD  20, 2, 5, 16, 19
	KHI_STEP_R1    ands, r3, r4, r5, r6, 10, r1, r2, 15
	KHI_STEP_R1    orrs, r7, r8, r5, r6, 10, r3, r4, 16
	KHI_STEP_R2    orns, r10, r11, r7, r8, r5, r6, 10, 17
	mvn.w	r7, r7
	mvn	r8, r8
	KHI_STEP       ands, r1, r2, r10, r11, r7, r8, 18
	KHI_STEP       orrs, r1, r2, r3, r4, r10, r11, 19

	@ A[2], A[8], A[14], A[15] and A[21]
	KHI_LOAD  10, 13, 22, 6, 9
	KHI_STEP_R1    bics, r5, r6, r3, r4, 55, r1, r2, 20
	KHI_STEP_R1R2  ands, r1, r2, r3, r4, 55, r10, r11, 2, 24
	mvns	r3, r3
	mvns	r4, r4
	KHI_STEP_R2    orrs, r7, r8, r5, r6, r3, r4, 55, 21
	KHI_STEP_R1    ands, r7, r8, r10, r11, 2, r5, r6, 22
	KHI_STEP_R1    orrs, r1, r2, r10, r11, 2, r7, r8, 23

	@ Get round counter XOR round constant into A[0]
	vmov	r1, s16
	adr	r2, .process_block_RC
	add.w	r2, r2, r1
	ldm	r2, { r3, r4 }
	ldm	r0, { r5, r6 }
	eors	r5, r3
	eors	r6, r4
	stm	r0, { r5, r6 }

	@ Increment round counter, loop until all 24 rounds are done.
	adds	r1, #8
	vmov	s16, r1
	cmp	r1, #192
	blo	process_block_loop

	@ Flush state words which were cached in FP registers.
	@ Apparently two successive str can execute in one cycle each
	@ if they bith use 16-bit encoding, while strd takes three cycles.
	vmov	r2, r3, s0, s1
	str	r2, [r0, #32]
	str	r3, [r0, #36]
	vmov	r2, r3, s2, s3
	str	r2, [r0, #72]
	str	r3, [r0, #76]
	vmov	r2, r3, s4, s5
	str	r2, [r0, #112]
	str	r3, [r0, #116]
	vmov	r2, r3, s6, s7
	strd	r2, r3, [r0, #152]
	vmov	r2, r3, s8, s9
	strd	r2, r3, [r0, #192]

	INVERT_WORDS

	add	sp, #200
	pop	{ r1 }
	vmov	s16, r1
	pop	{ r4, r5, r6, r7, r8, r10, r11, pc }

	.align	2
.process_block_RC:
	.word	0x00000001
	.word	0x00000000
	.word	0x00008082
	.word	0x00000000
	.word	0x0000808A
	.word	0x80000000
	.word	0x80008000
	.word	0x80000000
	.word	0x0000808B
	.word	0x00000000
	.word	0x80000001
	.word	0x00000000
	.word	0x80008081
	.word	0x80000000
	.word	0x00008009
	.word	0x80000000
	.word	0x0000008A
	.word	0x00000000
	.word	0x00000088
	.word	0x00000000
	.word	0x80008009
	.word	0x00000000
	.word	0x8000000A
	.word	0x00000000
	.word	0x8000808B
	.word	0x00000000
	.word	0x0000008B
	.word	0x80000000
	.word	0x00008089
	.word	0x80000000
	.word	0x00008003
	.word	0x80000000
	.word	0x00008002
	.word	0x80000000
	.word	0x00000080
	.word	0x80000000
	.word	0x0000800A
	.word	0x00000000
	.word	0x8000000A
	.word	0x80000000
	.word	0x80008081
	.word	0x80000000
	.word	0x00008080
	.word	0x80000000
	.word	0x80000001
	.word	0x00000000
	.word	0x80008008
	.word	0x80000000

	.size	fndsa_sha3_process_block,.-fndsa_sha3_process_block
