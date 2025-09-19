# Kbuild Makefile for DKMS
obj-m += snd-hda-codec-cs8409.o

# Objektliste des Moduls
snd-hda-codec-cs8409-y := \
  patch_cs8409.o \
  patch_cs8409-tables.o

# (Keine ccflags/EXTRA_CFLAGS hier – die kommen aus dkms.conf)
# Optional:
# all:
# 	$(MAKE) -C $(KDIR) M=$(PWD) modules
# clean:
# 	$(MAKE) -C $(KDIR) M=$(PWD) clean
ccflags-y += -I$(src)
ccflags-y += -Wno-error
ccflags-y += -DAPPLE_PINSENSE_FIXUP
ccflags-y += -DAPPLE_CODECS
ccflags-y += -DCONFIG_SND_HDA_RECONFIG
ccflags-y += -DCONFIG_SND_HDA_PATCH_LOADER
ccflags-y += -Wno-unused-variable
ccflags-y += -Wno-unused-function
ccflags-y += -Wno-empty-body
ccflags-y += -Wno-missing-prototypes
