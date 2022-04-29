mkdir build
nasm -f elf64 "Bootloader/header.asm" -o "build/header.o"
nasm -f elf64 "Bootloader/boot.asm" -o "build/boot.o"
# nasm -f elf64 "Bootloader/boot64.asm" -o "build/boot64.o"

gcc -o ./build/main.o -c -I -ffreestanding ./kernel/main.c

# ld -n -o "build/kernel.bin" -T "linker.ld" "build/main.o" "build/header.o" "build/boot64.o" "build/boot.o"
ld -n -o "build/kernel.bin" -T "linker.ld" "build/main.o" "build/header.o" "build/boot.o"
cp "build/kernel.bin" "iso/boot/kernel.bin"
grub-mkrescue -o "os.iso" "iso" -d "/usr/lib/grub/i386-pc"