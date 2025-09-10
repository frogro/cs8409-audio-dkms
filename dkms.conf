# --- top of Makefile ---
obj-m := snd-hda-codec-cs8409.o
snd-hda-codec-cs8409-y := patch_cs8409.o patch_cs8409-tables.o

# Alle nötigen Defines/Warnings ohne Anführungszeichen:
ccflags-y += -DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1
ccflags-y += -Wno-unused-variable -Wno-unused-function

# KDIR sauber aus KERNELRELEASE ableiten (DKMS setzt das)
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
