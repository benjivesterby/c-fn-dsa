/*
 * This file is part of the libopencm3 project.
 *
 * Copyright (C) 2009 Uwe Hermann <uwe@hermann-uwe.de>
 * Copyright (C) 2011 Stephen Caudle <scaudle@doceme.com>
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 */

/* Linker script for ST STM32F4DISCOVERY (STM32F407G-DISC1, 1024K flash, 192K RAM). */

/* Define memory regions. */
MEMORY
{
	/*
	 * We use the CCM block for RAM; it's only 64 kB and it is not
	 * usable for DMA to peripheral, but it makes things run about
	 * 10% faster because it removes some contention with instruction
	 * fetching.
	 */
	rom (rx) : ORIGIN = 0x08000000, LENGTH = 1024K
	ram (rwx) : ORIGIN = 0x10000000, LENGTH = 64K

	/* ram (rwx) : ORIGIN = 0x20000000, LENGTH = 128K */
}

/* Include the common ld script.
   ADJUST PATH HERE */
INCLUDE ../../libopencm3/lib/cortex-m-generic.ld
