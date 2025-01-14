#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>

#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/gpio.h>
#include <libopencm3/stm32/usart.h>
#include <libopencm3/stm32/flash.h>

#include "inner.h"

/* Send len copies of character c onto the output UART. */
static void
send_mult_chars(char c, size_t len)
{
	size_t u;

	for (u = 0; u < len; u ++) {
		usart_send_blocking(USART2, c);
	}
}

/* Send a string (len characters, starting at s) to the UART. If
   len < olen, then padding is added, consisting olen-len copies
   of pad. If pad_left is non-zero then the padding is sent before
   the string, otherwise it is sent after the string. */
static void
send_string(const char *s, size_t len, size_t olen, char pad, int pad_left)
{
	size_t u;

	if (len < olen && pad_left) {
		send_mult_chars(pad, olen - len);
	}
	for (u = 0; u < len; u ++) {
		usart_send_blocking(USART2, s[u]);
	}
	if (len < olen && !pad_left) {
		send_mult_chars(pad, olen - len);
	}
}

/* Convert unsigned intger x to characters, using the provided base.
   Base can be up to 36; ASCII letters 'A' to 'Z' are used for digit
   values 10 to 35 (if upper is zero, then lowercase letters 'a' to 'z'
   are used instead). Output is written into buf[] (with no terminating
   zero) and the number of produced characters is returned. */
static size_t
to_digits(char *buf, uint64_t x, unsigned base, int upper)
{
	size_t u, v;

	u = 0;
	while (x != 0) {
		unsigned d;

		d = (x % base);
		x /= base;
		if (d >= 10) {
			if (upper) {
				d += 'A' - 10;
			} else {
				d += 'a' - 10;
			}
		} else {
			d += '0';
		}
		buf[u ++] = d;
	}
	if (u == 0) {
		buf[u ++] = '0';
	}
	for (v = 0; (v + v) < u; v ++) {
		char t;

		t = buf[v];
		buf[v] = buf[u - 1 - v];
		buf[u - 1 - v] = t;
	}
	return u;
}

/* Send an unsigned 64-bit integer to the UART. The integer is converted
   to digits with the provided base and 'upper' flag (see to_digits()).
   If the converted value is shorter than olen characters, then padding
   is applied, with enough '0' characters (if pad0 != 0) or spaces (if
   pad0 == 0). The pad_left flag determines if the padding comes before
   (pad_left != 0) or after (pad_left == 0) the converted integer.
   When trailing padding is used (pad_left == 0), the padding always
   uses spaces. */
static void
send_uint64(uint64_t x, unsigned base, int upper,
	size_t olen, int pad0, int pad_left)
{
	char buf[65];
	size_t u;

	u = to_digits(buf, x, base, upper);
	send_string(buf, u, olen, (pad0 && pad_left) ? '0' : ' ', pad_left);
}

/* Same as send_uint64() but for a signed integer. A leading '-' is used
   if necessary; leading padding (if any) is put before the '-' sign if
   it uses spaces, but after the '-' sign if it uses zeros. Trailing padding
   always consists of spaces regardless of 'pad0'. */
static void
send_int64(int64_t x, unsigned base, int upper,
	size_t olen, int pad0, int pad_left)
{
	char buf[65];
	size_t u;

	if (x < 0) {
		u = to_digits(buf, -(uint64_t)x, base, upper);
		if (pad_left) {
			if (pad0) {
				usart_send_blocking(USART2, '-');
				if (olen > (u + 1)) {
					send_mult_chars('0', olen - (u + 1));
				}
			} else {
				if (olen > (u + 1)) {
					send_mult_chars(' ', olen - (u + 1));
				}
				usart_send_blocking(USART2, '-');
			}
			send_string(buf, u, 0, 0, 0);
		} else {
			usart_send_blocking(USART2, '-');
			if (olen > 0) {
				olen --;
			}
			send_string(buf, u, olen, ' ', 0);
		}
	} else {
		u = to_digits(buf, x, base, upper);
		send_string(buf, u, olen, pad0 ? '0' : ' ', pad_left);
	}
}

/* A printf()-lookalike. Each format element has the following format:
     %[-][0][len][w]type
   with:
      -      Padding is applied after the value instead of before the value
      0      Integer padding uses leading zeros instead of spaces
      len    Target output length (decimal)
      w      For an integer value: value is wide (64-bit)
      type   One of:
                d   signed integer (decimal)
		u   unsigned integer (decimal)
		x   unsigned integer (hexadecimal, lowercase)
		X   unsigned integer (hexadecimal, uppercase)
		s   nul-terminated character string
   The '0' flag is ignored for strings; padding, if any, always uses spaces.
   Conventionally, '%%' should be used to emit a '%' character. */
void
prf(const char *fmt, ...)
{
	va_list ap;
	const char *c;

	va_start(ap, fmt);
	c = fmt;
	for (;;) {
		int d;
		int pad0, wide, pad_left;
		unsigned olen;

		d = *c ++;
		if (d == 0) {
			break;
		}
		if (d != '%') {
			usart_send_blocking(USART2, d);
			continue;
		}
		d = *c ++;
		pad0 = 0;
		olen = 0;
		wide = 0;
		pad_left = 1;
		if (d == '-') {
			pad_left = 0;
			d = *c ++;
		}
		if (d >= '0' && d <= '9') {
			if (d == '0') {
				pad0 = 1;
			}
			while (d >= '0' && d <= '9') {
				olen = 10 * olen + (d - '0');
				d = *c ++;
			}
		}
		if (d == 'w') {
			wide = 1;
			d = *c ++;
		}
		if (pad0 && !pad_left) {
			pad0 = 0;
		}
		switch (d) {
		case 'd': {
			int64_t x;

			if (wide) {
				x = va_arg(ap, int64_t);
			} else {
				x = va_arg(ap, int32_t);
			}
			send_int64(x, 10, 0, olen, pad0, pad_left);
			break;
		}
		case 'u': {
			uint64_t x;

			if (wide) {
				x = va_arg(ap, uint64_t);
			} else {
				x = va_arg(ap, uint32_t);
			}
			send_uint64(x, 10, 0, olen, pad0, pad_left);
			break;
		}
		case 'x': {
			uint64_t x;

			if (wide) {
				x = va_arg(ap, uint64_t);
			} else {
				x = va_arg(ap, uint32_t);
			}
			send_uint64(x, 16, 0, olen, pad0, pad_left);
			break;
		}
		case 'X': {
			uint64_t x;

			if (wide) {
				x = va_arg(ap, uint64_t);
			} else {
				x = va_arg(ap, uint32_t);
			}
			send_uint64(x, 16, 1, olen, pad0, pad_left);
			break;
		}
		case 's': {
			const char *s;

			s = va_arg(ap, const char *);
			send_string(s, strlen(s), olen, ' ', pad_left);
			break;
		}
		case 0:
			break;
		default:
			usart_send_blocking(USART2, '%');
			break;
		}
		if (d == 0) {
			break;
		}
	}
	va_end(ap);
}

/* 24 MHz */
const struct rcc_clock_scale benchmarkclock = {
	.pllm = 8, //VCOin = HSE / PLLM = 1 MHz
	.plln = 192, //VCOout = VCOin * PLLN = 192 MHz
	.pllp = 8, //PLLCLK = VCOout / PLLP = 24 MHz (low to have 0WS)
	.pllq = 4, //PLL48CLK = VCOout / PLLQ = 48 MHz (required for USB, RNG)
	.pllr = 0,
	.pll_source = RCC_CFGR_PLLSRC_HSE_CLK,
	.hpre = RCC_CFGR_HPRE_DIV_NONE,
	.ppre1 = RCC_CFGR_PPRE_DIV_2,
	.ppre2 = RCC_CFGR_PPRE_DIV_NONE,
	.voltage_scale = PWR_SCALE1,
	.flash_config = FLASH_ACR_DCEN | FLASH_ACR_ICEN | FLASH_ACR_LATENCY_0WS,
	.ahb_frequency  = 24000000,
	.apb1_frequency = 12000000,
	.apb2_frequency = 24000000,
};

/* Enable the cycle counter. */
static void
enable_cyccnt(void)
{
	volatile uint32_t *DWT_CONTROL = (volatile uint32_t *)0xE0001000;
	volatile uint32_t *DWT_CYCCNT = (volatile uint32_t *)0xE0001004;
	volatile uint32_t *DEMCR = (volatile uint32_t *)0xE000EDFC;
	volatile uint32_t *LAR  = (volatile uint32_t *)0xE0001FB0;

	*DEMCR = *DEMCR | 0x01000000;
	*LAR = 0xC5ACCE55;
	*DWT_CYCCNT = 0;
	*DWT_CONTROL = *DWT_CONTROL | 1;
}

/* Read the current cycle count. */
static inline uint32_t
get_system_ticks(void)
{
	return *(volatile uint32_t *)0xE0001004;
}

/*
static void
sort_times(uint32_t *tt, size_t num)
{
	for (size_t u = num; u > 0; u --) {
		uint32_t x = tt[0];
		for (size_t v = 1; v < u; v ++) {
			uint32_t y = tt[v];
			if (x > y) {
				tt[v - 1] = y;
				tt[v] = x;
			} else {
				x = y;
			}
		}
	}
}
*/

static inline uint32_t
dec32le(const void *src)
{
	const uint8_t *buf = src;
	return (uint32_t)buf[0]
		| ((uint32_t)buf[1] << 8)
		| ((uint32_t)buf[2] << 16)
		| ((uint32_t)buf[3] << 24);
}

static inline void
enc32le(void *dst, uint32_t x)
{
	uint8_t *buf = dst;
	buf[0] = (uint8_t)x;
	buf[1] = (uint8_t)(x >> 8);
	buf[2] = (uint8_t)(x >> 16);
	buf[3] = (uint8_t)(x >> 24);
}

/* FREQ should be 24 or 168 (for 24 MHz or 168 MHz operations). Default
   is 24. At 24 MHz, memory accesses have minimal (1-cycle) latency and
   there are no prefetch or cache effects; it is the traditional speed
   used in the literature for benchmarking cryptographic algorithms.
   Note that in-CPU contention between instruction fetching and data
   accesses can still happen at 24 MHz. */
#ifndef FREQ
#define FREQ   24
#endif

int
main(void)
{
	/* Setup clock. */
#if FREQ == 24
	rcc_clock_setup_pll(&benchmarkclock);
#elif FREQ == 168
	rcc_clock_setup_pll(&rcc_hse_8mhz_3v3[RCC_CLOCK_3V3_168MHZ]);
#else
#error Unsupported frequency
#endif

	/* Configure I/O. */
	rcc_periph_clock_enable(RCC_GPIOD);
	rcc_periph_clock_enable(RCC_GPIOA);
	rcc_periph_clock_enable(RCC_USART2);

	gpio_mode_setup(GPIOD, GPIO_MODE_OUTPUT,
		GPIO_PUPD_NONE, GPIO12 | GPIO13 | GPIO14 | GPIO15);
	gpio_mode_setup(GPIOA, GPIO_MODE_AF, GPIO_PUPD_NONE, GPIO2);
	gpio_set_af(GPIOA, GPIO_AF7, GPIO2);

	usart_set_baudrate(USART2, 115200);
	usart_set_databits(USART2, 8);
	usart_set_stopbits(USART2, USART_STOPBITS_1);
	usart_set_mode(USART2, USART_MODE_TX);
	usart_set_parity(USART2, USART_PARITY_NONE);
	usart_set_flow_control(USART2, USART_FLOWCONTROL_NONE);

	/* Finally enable the USART. */
	usart_enable(USART2);

	/*
	 * Enable cycle counter.
	 */
	enable_cyccnt();

	/*
	 * We display a banner which shows the current Flash flags.
	 *   0x0100   enable prefetch flag
	 *   0x0200   enable instruction cache flag
	 *   0x0400   enable data cache flag
	 * At 24 MHz everything should be disabled (the CPU is slow enough
	 * that Flash reads work with minimal latency). At 168 MHz we
	 * want all three active, otherwise performance is terrible.
	 */
	prf("-----------------------------------------\n");
	prf("FLASH_ACR (orig): %08X\n", *(volatile uint32_t *)0x40023C00);
#if FREQ == 24
	*(volatile uint32_t *)0x40023C00 &= (uint32_t)0x0000;
#elif FREQ == 168
	*(volatile uint32_t *)0x40023C00 |= (uint32_t)0x0700;
#else
#error Unsupported frequency
#endif
	prf("FLASH_ACR (set):  %08X\n", *(volatile uint32_t *)0x40023C00);
	prf("--------------------------------------------------------\n");

	/* Statically allocated arrays for objects (so that stack use
	   remains small). */
	static uint8_t skey[FNDSA_SIGN_KEY_SIZE(10)];
	static uint8_t vkey[FNDSA_VRFY_KEY_SIZE(10)];
	static uint8_t sig[FNDSA_SIGN_KEY_SIZE(10)];
	static uint8_t tmp_small[78 * 512 + 31];

	/* RAM is the CCM block. For logn=10, we need to use the extra
	   RAM block (128 kB at address 0x20000000), which is a bit slower
	   since it can get into some contention with instruction fetching. */
	static uint8_t *tmp_big = (uint8_t *)(uintptr_t)0x20000000;

	/* An pointer to an aligned buffer (of size at least 39936 bytes). */
	void *tmp_aligned = (void *)
		(((uintptr_t)tmp_small + 31) & ~(uintptr_t)31);

	/* Some bench functions for small primitives. Returned value
	   is the time taken. These primitives have a constant execution
	   time (independent of the input values). Some need extra
	   parameters:
	       bench_keccak()   200-byte buffer
	       bench_NTT()      degree (logn, 2 to 10) and 2*n-byte buffer
	       bench_iNTT()     degree (logn, 2 to 10) and 2*n-byte buffer
	   Provided buffers need not be initialized but should be suitably
	   aligned.
	   bench_none() is for a do-nothing trivial function whose inherent
	   cost should be 2 cycles (a single 'bx lr' opcode). It is used
	   for calibration. */
	extern uint32_t bench_none(void);
	extern uint32_t bench_scaled(void);
	extern uint32_t bench_add(void);
	extern uint32_t bench_mul(void);
	extern uint32_t bench_div(void);
	extern uint32_t bench_sqrt(void);
	extern uint32_t bench_keccak(uint64_t *A);
	extern uint32_t bench_NTT(unsigned logn, uint16_t *d);
	extern uint32_t bench_iNTT(unsigned logn, uint16_t *d);

	/* bench_none() measures a function with inherent cost 2 cycles. */
	uint32_t cal = bench_none() - 2;
	prf("fpr_scaled: %5u\n", bench_scaled() - cal);
	prf("fpr_add:    %5u\n", bench_add() - cal);
	prf("fpr_mul:    %5u\n", bench_mul() - cal);
	prf("fpr_div:    %5u\n", bench_div() - cal);
	prf("fpr_sqrt:   %5u\n", bench_sqrt() - cal);
	prf("keccak:     %5u\n", bench_keccak(tmp_aligned) - cal);
	prf("NTT:        n=256: %5u   n=512: %5u   n=1024: %5u\n",
		bench_NTT(8, tmp_aligned) - cal,
		bench_NTT(9, tmp_aligned) - cal,
		bench_NTT(10, tmp_aligned) - cal);
	prf("iNTT:       n=256: %5u   n=512: %5u   n=1024: %5u\n",
		bench_iNTT(8, tmp_aligned) - cal,
		bench_iNTT(9, tmp_aligned) - cal,
		bench_iNTT(10, tmp_aligned) - cal);

	/* For each degree, we make one measurement with a reproducible
	   seed value. Seed was chosen such that the hash-to-point cost
	   is the "high" one (hash-to-point uses a variable amount of
	   SHAKE256 output, which in turn implies a variable number of
	   invocations of Keccak-f. We consider the two most common numbers
	   of calls to Keccak-f, and the seed exercises the higher of these
	   two numbers.
	   We also record the signing time as a "reference" value so as
	   to detect restarts. */
	uint32_t ref_time_sign[3];
	for (unsigned logn = 8; logn <= 10; logn ++) {
		uint8_t seed[2];
		seed[0] = (uint8_t)logn;
		seed[1] = logn == 9 ? 3 : 0;
		uint8_t *tmp = logn < 10 ? tmp_small : tmp_big;
		size_t tmp_len = ((size_t)78 << logn) + 31;
		size_t skey_len = FNDSA_SIGN_KEY_SIZE(logn);
		size_t vkey_len = FNDSA_VRFY_KEY_SIZE(logn);
		size_t sig_len = FNDSA_SIGNATURE_SIZE(logn);
		uint32_t begin, end;

		begin = get_system_ticks();
		if (!fndsa_keygen_seeded_temp(logn, seed, sizeof seed,
			skey, vkey, tmp, tmp_len))
		{
			prf("ERR keygen\n");
			break;
		}
		end = get_system_ticks();
		uint32_t time_kgen = end - begin;

		shake_context *sc = tmp_aligned;
		begin = get_system_ticks();
		shake_init(sc, 256);
		shake_inject(sc, vkey, vkey_len);
		shake_flip(sc);
		shake_extract(sc, tmp_aligned, 64);
		end = get_system_ticks();
		uint32_t time_hpk = end - begin;

		size_t j;
		begin = get_system_ticks();
		if (logn >= 9) {
			j = fndsa_sign_seeded_temp(skey, skey_len,
				NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
				seed, sizeof seed, sig, sig_len, tmp, tmp_len);
		} else {
			j = fndsa_sign_weak_seeded_temp(skey, skey_len,
				NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
				seed, sizeof seed, sig, sig_len, tmp, tmp_len);
		}
		end = get_system_ticks();
		if (j != sig_len) {
			prf("ERR sign: %u\n", j);
			break;
		}
		uint32_t time_sign = end - begin;
		ref_time_sign[logn - 8] = time_sign;

		int r;
		begin = get_system_ticks();
		if (logn >= 9) {
			r = fndsa_verify_temp(sig, sig_len, vkey, vkey_len,
				NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
				tmp, tmp_len);
		} else {
			r = fndsa_verify_weak_temp(sig, sig_len, vkey, vkey_len,
				NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
				tmp, tmp_len);
		}
		if (!r) {
			prf("ERR verify\n");
			break;
		}
		end = get_system_ticks();
		uint32_t time_vrfy = end - begin;

		prf("FN-DSA(n = %4u)"
			"  kgen: %9u  sign: %8u  vrfy: %6u  hpk: %6u\n",
			1u << logn, time_kgen, time_sign, time_vrfy, time_hpk);
	}

	/* Long-run measurements. */
	uint64_t total_kgen[3] = { 0, 0, 0 };
	uint64_t total_sign[3] = { 0, 0, 0 };
	uint64_t total_sign_restart[3] = { 0, 0, 0 };
	uint64_t total_vrfy[3] = { 0, 0, 0 };
	uint32_t total_num_restart[3] = { 0, 0, 0 };
	for (uint32_t total_num = 1;; total_num ++) {
		for (unsigned logn = 8; logn <= 10; logn ++) {
			uint8_t seed[5];
			seed[0] = (uint8_t)logn;
			enc32le(seed + 1, total_num);
			uint8_t *tmp = logn < 10 ? tmp_small : tmp_big;
			size_t tmp_len = ((size_t)78 << logn) + 31;
			size_t skey_len = FNDSA_SIGN_KEY_SIZE(logn);
			size_t vkey_len = FNDSA_VRFY_KEY_SIZE(logn);
			size_t sig_len = FNDSA_SIGNATURE_SIZE(logn);
			uint32_t begin, end;

			begin = get_system_ticks();
			if (!fndsa_keygen_seeded_temp(logn, seed, sizeof seed,
				skey, vkey, tmp, tmp_len))
			{
				prf("ERR keygen\n");
				break;
			}
			end = get_system_ticks();
			uint32_t time_kgen = end - begin;

			size_t j;
			begin = get_system_ticks();
			if (logn >= 9) {
				j = fndsa_sign_seeded_temp(skey, skey_len,
					NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
					seed, sizeof seed,
					sig, sig_len, tmp, tmp_len);
			} else {
				j = fndsa_sign_weak_seeded_temp(skey, skey_len,
					NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
					seed, sizeof seed,
					sig, sig_len, tmp, tmp_len);
			}
			end = get_system_ticks();
			if (j != sig_len) {
				prf("ERR sign: %u\n", j);
				break;
			}
			uint32_t time_sign = end - begin;
			ref_time_sign[logn - 8] = time_sign;

			int r;
			begin = get_system_ticks();
			if (logn >= 9) {
				r = fndsa_verify_temp(
					sig, sig_len, vkey, vkey_len,
					NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
					tmp, tmp_len);
			} else {
				r = fndsa_verify_weak_temp(
					sig, sig_len, vkey, vkey_len,
					NULL, 0, FNDSA_HASH_ID_RAW, "blah", 4,
					tmp, tmp_len);
			}
			if (!r) {
				prf("ERR verify\n");
				break;
			}
			end = get_system_ticks();
			uint32_t time_vrfy = end - begin;

			total_kgen[logn - 8] += time_kgen;
			total_sign[logn - 8] += time_sign;
			total_vrfy[logn - 8] += time_vrfy;
			uint32_t rts = ref_time_sign[logn - 8];
			if (time_sign > (rts + (rts >> 1))) {
				total_sign_restart[logn - 8] += time_sign;
				total_num_restart[logn - 8] ++;
			}
		}

		if (total_num <= 10 || (total_num % 100) == 0) {
			uint32_t nu = total_num;
			uint32_t na = nu >> 1;
			prf("\nnum = %u\n", nu);
			for (unsigned logn = 8; logn <= 10; logn ++) {
				uint32_t tk, ts, ts2, tv, rs;
				tk = (total_kgen[logn - 8] + na) / nu;
				ts = (total_sign[logn - 8] + na) / nu;
				tv = (total_vrfy[logn - 8] + na) / nu;
				rs = total_num_restart[logn - 8];
				if (rs == nu) {
					ts2 = 0;
				} else {
					uint32_t nu2 = nu - rs;
					ts2 = (total_sign[logn - 8]
						- total_sign_restart[logn - 8]
						+ (nu2 >> 1)) / nu;
				}
				prf("FN-DSA(n = %4u)  kg: %9u  sg: %8u"
					"  (%8u)  vf: %6u  rs=%u\n",
					1u << logn, tk, ts, ts2, tv, rs);
			}
		} else {
			prf(".");
		}
	}

	/* Blink the LED (PD12) on the board. */
	while (1) {
		int i;

		gpio_toggle(GPIOD, GPIO12);

		/* Upon button press, blink more slowly. */
		if (gpio_get(GPIOA, GPIO0)) {
			for (i = 0; i < 3000000; i++) {	/* Wait a bit. */
				__asm__("nop");
			}
		}

		for (i = 0; i < 3000000; i++) {		/* Wait a bit. */
			__asm__("nop");
		}
	}

	return 0;
}
