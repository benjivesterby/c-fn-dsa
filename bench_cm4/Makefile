# Benchmarking on an STM32F407G-DISC1 board ("Discovery" board, with an
# ARM Cortex-M4F microcontroller).
#
# To compile a "plain C" version (without use of assembly routines), set
# FNDSA_ASM_CORTEXM4 to 0 instead of 1 (in CFLAGS), and empty the contents
# of the OBJ_ASM variable.

CC = arm-none-eabi-gcc
CFLAGS = -Wall -Wextra -Wshadow -Wundef -Wno-cast-function-type -std=c99 -ggdb3 -O2 $(ARCHFLAGS) -fno-common -ffunction-sections -fdata-sections -I $(INCDIR) -DSTM32F4 -DFREQ=24 -DFNDSA_ASM_CORTEXM4=1
LD = arm-none-eabi-gcc
LDFLAGS = -L$(LIBDIR) --static -nostartfiles -T$(LDSCRIPT) -ggdb3 $(ARCHFLAGS) -Wl,--gc-sections
LIBS = -lopencm3_stm32f4 -Wl,--start-group -lc -lgcc -lm -lnosys -Wl,--end-group
ARCHFLAGS = -mthumb -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16

# ADJUST THESE VALUES
INCDIR = ../../libopencm3/include
LIBDIR = ../../libopencm3/lib
LDSCRIPT = stm32f4-discovery.ld

OBJ_COMM = codec.o mq.o sha3.o sysrng.o util.o
OBJ_COMM_ASM = codec_cm4.o mq_cm4.o sha3_cm4.o
OBJ_KGEN = kgen.o kgen_fxp.o kgen_gauss.o kgen_mp31.o kgen_ntru.o kgen_poly.o kgen_zint31.o
OBJ_SIGN = sign.o sign_core.o sign_fpoly.o sign_fpr.o sign_sampler.o
OBJ_SIGN_ASM = sign_fpr_cm4.o sign_sampler_cm4.o
OBJ_VRFY = vrfy.o
OBJ_ASM = $(OBJ_COMM_ASM) $(OBJ_SIGN_ASM)
OBJ = $(OBJ_COMM) $(OBJ_KGEN) $(OBJ_SIGN) $(OBJ_VRFY) $(OBJ_ASM)
OBJ_TIMING = timing.o bench_cm4.o

all: timing.elf

clean:
	-rm -f $(OBJ) $(OBJ_TIMING) timing.elf

timing.elf: $(OBJ) $(OBJ_TIMING)
	$(LD) $(LDFLAGS) -o timing.elf $(OBJ) $(OBJ_TIMING) $(LIBS)

timing.o: timing.c ../fndsa.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o timing.o timing.c

bench_cm4.o: bench_cm4.s
	$(CC) $(CFLAGS) -I.. -c -o bench_cm4.o bench_cm4.s

# -----------------------------------------------------------------------

codec.o: ../codec.c ../fndsa.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o codec.o ../codec.c

codec_cm4.o: ../codec_cm4.s
	$(CC) $(CFLAGS) -I.. -c -o codec_cm4.o ../codec_cm4.s

mq.o: ../mq.c ../fndsa.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o mq.o ../mq.c

mq_cm4.o: ../mq_cm4.s
	$(CC) $(CFLAGS) -I.. -c -o mq_cm4.o ../mq_cm4.s

sha3.o: ../sha3.c ../fndsa.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o sha3.o ../sha3.c

sha3_cm4.o: ../sha3_cm4.s
	$(CC) $(CFLAGS) -I.. -c -o sha3_cm4.o ../sha3_cm4.s

sysrng.o: ../sysrng.c ../fndsa.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o sysrng.o ../sysrng.c

util.o: ../util.c ../fndsa.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o util.o ../util.c

kgen.o: ../kgen.c ../fndsa.h ../kgen_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o kgen.o ../kgen.c

kgen_fxp.o: ../kgen_fxp.c ../fndsa.h ../kgen_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o kgen_fxp.o ../kgen_fxp.c

kgen_gauss.o: ../kgen_gauss.c ../fndsa.h ../kgen_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o kgen_gauss.o ../kgen_gauss.c

kgen_mp31.o: ../kgen_mp31.c ../fndsa.h ../kgen_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o kgen_mp31.o ../kgen_mp31.c

kgen_ntru.o: ../kgen_ntru.c ../fndsa.h ../kgen_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o kgen_ntru.o ../kgen_ntru.c

kgen_poly.o: ../kgen_poly.c ../fndsa.h ../kgen_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o kgen_poly.o ../kgen_poly.c

kgen_zint31.o: ../kgen_zint31.c ../fndsa.h ../kgen_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o kgen_zint31.o ../kgen_zint31.c

sign.o: ../sign.c ../fndsa.h ../sign_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o sign.o ../sign.c

sign_core.o: ../sign_core.c ../fndsa.h ../sign_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o sign_core.o ../sign_core.c

sign_fpoly.o: ../sign_fpoly.c ../fndsa.h ../sign_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o sign_fpoly.o ../sign_fpoly.c

sign_fpr.o: ../sign_fpr.c ../fndsa.h ../sign_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o sign_fpr.o ../sign_fpr.c

sign_fpr_cm4.o: ../sign_fpr_cm4.s
	$(CC) $(CFLAGS) -I.. -c -o sign_fpr_cm4.o ../sign_fpr_cm4.s

sign_sampler.o: ../sign_sampler.c ../fndsa.h ../sign_inner.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o sign_sampler.o ../sign_sampler.c

sign_sampler_cm4.o: ../sign_sampler_cm4.s
	$(CC) $(CFLAGS) -I.. -c -o sign_sampler_cm4.o ../sign_sampler_cm4.s

vrfy.o: ../vrfy.c ../fndsa.h ../inner.h
	$(CC) $(CFLAGS) -I.. -c -o vrfy.o ../vrfy.c
