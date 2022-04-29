global start
extern kernel_main

section .text
bits 32
start:
	mov esp, stack_top

	call check_multiboot 	; checks if we loaded with multiboot
	call check_cpuid 		; Check for a CPU ID
	call check_long_mode 	; Check if 64-bit is supported

	; Setup memory management & enable paging. Even though we now have 64-bit pages, processor is still
	; in a 32-bit compatibility mode. 
	call setup_page_tables
	call enable_paging

	; ; To execute 64-bit code, we need to setup a global descriptor table. 
	; ; This table is for backwards compatibility for older system. GDT is used for segmentation rather than paging
	; ; in older operating systems. Even though we dont use segmentation, we still need to define a GDT.
	lgdt [gdt64.pointer] 	; This loads the GDT register so that we actually enter 64-bit mode.

	; ; Now we have to do some cleanup. We loaded the code segment register CS with GDT offset. However, the data registers
	; ; ss, ds, es, fs and gs still contain data segment offsets of the old GDT. To avoid problems, set all of these to null.
	call long_mode_start

	; print `OK`
	; mov dword [0xb8000], 0x2f4b2f4f ; VGA memory starts at 0xB8000
	call kernel_main
	hlt							; halt execution


check_multiboot:
	cmp eax, 0x36D76289 	; All compliant bootloaders will have this value in EAX register
	jne .no_multiboot		; jne: if value of comparison is 0 (false, comparison was not equal) jump to no multiboot. If value is not in register, jump to failure
	ret	
.no_multiboot:
	mov al, "M"		; Move error code into one of CPU registers (AL register is 8 bit)
	jmp error		; Trigger error message to be shown


; If we can flip CPUID bit in the flags register, then CPUID is avilable.
; bit 21 in the FLAGS register is the ID bit.
; Checking CPUID is required because only when we have CPUID, we can figure out if 64-bit execution is supported.
check_cpuid:
	; Copy FLAGS register to EAX register via our stack
	pushfd
	pop eax

	; Copy ECX as well, for comparison later on
	mov ecx, eax

	; 21st bit is the ID bit of the CPU. If we can flip it, CPUID is available.
	xor eax, 1 << 21

	; Copy EAX to the FLAGS register
	push eax
	popfd

	; Copy FLAGS back to EAX. The bit should remain flipped if CPUID is supported.
	pushfd
	pop eax

	; Restore FLAGS from the old version stored in ECX register (see line 'mov ecx, eax')
	push ecx
	popfd

	; Compare EAX and ECX. If they are equal, the bit was not flipped and no CPUID is available.
	cmp eax, ecx
	je .no_cpuid	; je: if value of cmp is 1 (true, they are equal) then do jump
	ret
.no_cpuid:
	mov al, "I"		; Store error code in AL register
	jmp error


check_long_mode:
	; Test if extended processor info is available
	mov eax, 0x80000000		; Argument for CPUID
	cpuid					; Gets the highest supported argument for CPUID, needs to be atleast 1 higher
	cmp eax, 0x80000001		; Compare if CPUID has extended info
	jb .no_long_mode		; jb: If the value in the EAX register is not incremented (below, jb = jump below) then jump to error.

	; Use extended info to test if longmode is available.
	mov eax, 0x80000001		; move extended info into EAX register
	cpuid					; returns some feature bits into ECX and EDX registers
	test edx, 1 << 29		; 29th bit is the long-mode bit. If it is present in EDX register, then long mode is supported
	jz .no_long_mode		; If the bit is 0, (jz = jump if zero) then no 64-bit support is available.
	ret
.no_long_mode:
	mov al, "L"		; Move error code L for long-mode to al register
	jmp error


error:
    mov dword [0xb8000], 0x4f524f45 ; VGA memory starts at 0xB8000. Print "E"
    mov dword [0xb8004], 0x4f3a4f52	; Print "R"
    mov dword [0xb8008], 0x4f204f20	; Print "R"
    mov byte  [0xb800a], al			; Print error code that is stored in al register.
    hlt								; return

; Upon creation of the .bss section by GRUB P4 will already be defined. 
setup_page_tables:
	; Map first p4 entry to p3 table
	mov eax, p3_table
	or eax, 0b11			; enable present & writeable flags
	mov [p4_table], eax		; Move flags of p3 table as an entry to the p4_table

	; Map first p3 entry to p2 table
	mov eax, p2_table
	or eax, 0b11
	mov [p3_table], eax

	; Huge-paging: By setting all 512 entries of the P2 table to point to 2 MiB of physical memory, we will end up with 1Gib of memory.
	; Lets create sort of a for-loop where the `i` for the loop is stored in the ECX register.
	mov ecx, 0
.map_p2_table:
	mov eax, 0x200000	; Store number of 2MiB in EAX register
	mul ecx				; By multiplying `i` by 2MiB, we will know the correct physical starting address of the next page. `i` is stored in ECX register.
	or eax, 0b10000011	; Last 2 bits are the present & writeable bits (line is mirrored). First bit is the huge flag. So our page entry is present, writeable and huge.
	mov [p2_table + ecx * 8], eax	; Each entry in the p2_table is 1 byte (8 bits). So in the P2 table, we tell where the 2MiB of physical memory can be found. 

	inc ecx				; Increase counter
	cmp ecx, 512		; If counter is equal to 512, return. Else, jump back to start of block.
	jne .map_p2_table
	ret

enable_paging:
	; CPU will look for the location of the P4 table in the CR3 register. Thus, we need to fill the value of the CR3 register with where our P4 table is located.
	mov eax, p4_table	; Put the P4 table location in EAX regsiter.
	mov cr3, eax		; Copy over the P4 register location to the CR3 register.

	; Enable physical address extension (PAE) (required for 64-bit paging)
	mov eax, cr4
	or eax, 1 << 5	; 5th bit is PAE flag. 
	mov cr4, eax

	; set long-mode flag to 1 to indicate we want to use 64-bit mode
	mov ecx, 0xC0000080		; Magic number that hints we want to enable 64-bit paging
	rdmsr					; This reads the model-specific register where we need to indicate we're in long mode
	or eax, 1 << 8			; Long-mode bit is at place 8 in the register. 
	wrmsr

	; Enable paging
	mov eax, cr0
	or eax, 1 << 31
	mov cr0, eax

	; Reset CR2 register
	mov eax, 0
	mov cr2, eax

	ret

long_mode_start:
    mov ax, 0
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
	ret

section .bss
align 4096		; Ensures the page tables are aligned with each other
p4_table:
	resb 4096	; This reserves the given amount of bytes in memory without initializing them. 
p3_table:
	resb 4096	; This reserves the given amount of bytes in memory without initializing them. 
p2_table:
	resb 4096	; This reserves the given amount of bytes in memory without initializing them. 
stack_bottom:
	resb 64
stack_top:

; Create a  read-only section 
; To execute 64-bit code, we need to setup a global descriptor table. 
; This table is for backwards compatibility for older system. GDT is used for segmentation rather than paging
; in older operating systems. Even though we dont use segmentation, we still need to define a GDT.
section .rodata
gdt64:
	dq 0 	; GDT always starts with a 0 bit
	dq (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53) 	; We need to define a code segment in our GDT. Set the following flags: 43 = executable, 44 needs to be 1 for code & data segments, 47 indicates it's present and 53 indicates the code segment is 64-bit.
.pointer:
	; Now we need to load our GDT. To do so, the CPU needs to know it's address and length. 
	; $ is the current address of the assembly code execution. Length of our GDT64 register is current location - gdt64 location (so $ - gdt64). -1 is required for convention.
	dw $ - gdt64 - 1	; first byte: length of our GDT table
	dq gdt64			; This specifies the location of the GDT table.
