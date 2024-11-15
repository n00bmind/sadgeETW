;  ========================================================================
;
;  (C) Copyright 2024 by Molly Rocket, Inc., All Rights Reserved.
;
;  This software is provided 'as-is', without any express or implied
;  warranty. In no event will the authors be held liable for any damages
;  arising from the use of this software.
;
;  Please see https://computerenhance.com for more information
;
;  ========================================================================

global CountNonZeroesWithBranch

section .text

CountNonZeroesWithBranch:
    xor rax, rax
    xor r10, r10

.loop:
    ; FIXME This destroys the rolling count of non-zeroes in rax, but for some extremely
    ; weird reason I cannot get the same results with Casey's test program if I use bl here!
    ; (even after pushing / popping rbx to the stack)
    mov al, [rdx + r10]
    
    cmp al, 0
    jz .skipsum
    inc rax
.skipsum:

    inc r10
    cmp r10, rcx
    jb .loop
    ret
