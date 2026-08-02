CFLAGS_applespi.o = -I$(src)	# for tracing

CONFIG_MODULE_SIG=n
CONFIG_MODULE_SIG_ALL=n
# CONFIG_MODULE_SIG_FORCE is not set 
# CONFIG_MODULE_SIG_SHA1 is not set
# CONFIG_MODULE_SIG_SHA224 is not set
# CONFIG_MODULE_SIG_SHA256 is not set
# CONFIG_MODULE_SIG_SHA384 is not set

KVERSION := $(KERNELRELEASE)
ifeq ($(origin KERNELRELEASE), undefined)
KVERSION := $(shell uname -r)
endif

ifneq ($(KVERSION),)
	ifeq ($(shell expr $(KVERSION) \< 5.3), 1)
		obj-m += applespi.o
	endif
endif

obj-m += apple-ibridge.o
obj-m += apple-ib-tb.o
obj-m += apple-ib-als.o

KDIR := /lib/modules/$(KVERSION)/build
PWD := $(shell pwd)

# Distros such as CachyOS/Arch-LLVM build the kernel with clang (often with
# ThinLTO). Such a kernel hands out cc-flags gcc cannot parse
# (-mstack-alignment=, -mretpoline-external-thunk, -fsplit-lto-unit), and a
# gcc-built module cannot be linked into an LTO kernel anyway. Detect it from
# the kernel's own config and switch the toolchain over automatically. Override
# by passing LLVM= explicitly on the command line.
ifeq ($(origin LLVM), undefined)
ifeq ($(shell grep -sq '^CONFIG_CC_IS_CLANG=y' $(KDIR)/include/config/auto.conf $(KDIR)/.config && echo y), y)
LLVM := 1
export LLVM
endif
endif

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install

test: all
	sync
	-rmmod applespi
	insmod ./applespi.ko
