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
