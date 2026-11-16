# GNU toolchain for the RV32I-only bare-metal build.
#
# CROSS_COMPILE=<prefix> selects a toolchain; otherwise scripts/toolchain.sh
# searches PATH for the usual prefixes. `make toolchain` validates the result.

# Prefer the GCC 15 toolchain in /opt/riscv over whatever PATH finds first
# (e.g. the old PULP GCC that `menu` puts in PATH, which lacks zicsr).
ifeq ($(strip $(CROSS_COMPILE)),)
ifneq ($(wildcard /opt/riscv/bin/riscv64-unknown-elf-gcc),)
CROSS_COMPILE := /opt/riscv/bin/riscv64-unknown-elf-
endif
endif

ifeq ($(strip $(CROSS_COMPILE)),)
CROSS_COMPILE := $(shell scripts/toolchain.sh --detect)
endif

ifeq ($(strip $(CROSS_COMPILE)),)
$(warning No RISC-V GNU toolchain in PATH; set CROSS_COMPILE=<prefix>)
endif

RV_CC      := $(CROSS_COMPILE)gcc
RV_AS      := $(CROSS_COMPILE)as
# Force the 32-bit emulation: a riscv64-* ld (or a riscv32-* symlink to one)
# defaults to elf64, which breaks `ld -r` on the RV32 objects.
RV_LD      := $(CROSS_COMPILE)ld -m elf32lriscv
RV_OBJDUMP := $(CROSS_COMPILE)objdump
RV_NM      := $(CROSS_COMPILE)nm
RV_SIZE    := $(CROSS_COMPILE)size

# RV32I plus Zicsr, which the cycle and instret reads need. No M, F or C.
RV_ARCH := -march=rv32i_zicsr -mabi=ilp32
