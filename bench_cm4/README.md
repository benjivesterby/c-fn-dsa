# Benchmarking on ARM Cortex-M4

This subdirectory contains some benchmarking code for an STM32F407-DISC1
board ("discovery" board featuring an STMicroelectronics microcontroller
with an ARM Cortex-M4F CPU).

## Compiling

 1. Get an embedded toolchain. On Ubuntu system, try installing the
    `gcc-arm-none-eabi` and `binutils-arm-none-eabi` packages.

 2. Download and compile [libopencm3](https://github.com/libopencm3/libopencm3).

 3. Update the `INCDIR` and `LIBDIR` variable in the [Makefile](Makefile)
    to point to where you put libopencm3 on your system. Similarly, update
    the `INCLUDE` directive at the end of
    [stm32f4-discovery.ld](stm32f4-discovery.ld).

 4. Type: `make`

    This should produce a binary file called `timing.elf`

In the Makefile, you can change `-DFNDSA_ASM_CORTEXM4=1` into
`-DFNDSA_ASM_CORTEXM4=0` (in the `CFLAGS` variable) to disable use of
the assembly-optimized routines; in that case, you must also empty the
contents of the `OBJ_ASM` variable (otherwise you'll get errors with
multiple functions with the same name). Benchmarking the plain C version
highlights the benefits of assembly optimizations (namely, using
assembly makes signature generation twice faster).

## Running

 1. Install [stlink](https://github.com/stlink-org/stlink). On Ubuntu systems,
    a system package exists, called `stlink-tools`.

 2. Install a "multi-architecture" version of GDB. On Ubuntu systems, you
    just install the `gdb-multiarch` package.

 3. Plug a serial console to the board. I am using a basic USB-to-TTL
    adapter cable; TX and RX go to pins PA3 and PA2, respectively. That
    adapter, on the host side, shows up in Linux as `/dev/ttyUSB0`. Set
    the speed with: `stty -F /dev/ttyUSB0 speed 115200 raw`

    Then type `cat /dev/ttyUSB0` in a terminal and let it run; this is
    where the benchmark program output will show up.

 4. Plug the board itself with its USB cable to the host system.

 5. Run in a terminal: `st-util -p 4500`

    This program should run as long as the board is in usage.

 6. In yet another terminal, run `gdb-multiarch`. In the GDB command-line,
    use the following commands:

    ~~~
    set arch arm
    target ext :4500
    load timing.elf
    run
    ~~~

You can interrupt (and debug!) the program by typing Ctrl-C in the
GDB command-line, then load a new version and run it again, and again.
