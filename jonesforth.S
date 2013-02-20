@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@
@ Jones' Forth port for ARM EABI
@ Copyright (C) 2013 M2IHP'13 class, see AUTHORS for the full list of
@ contributors.
@
@ Original x86 and forth code: Richard W.M. Jones <rich@annexia.org>
@
@ The extensive comments from Jones' x86 version have been removed.  You should
@ check them out, they are really detailed, well written and pedagogical.
@
@ The DIVMOD routine is taken from the ARM Software Development Toolkit User
@ Guide 2.50.
@
@ This program is free software: you can redistribute it and/or modify it under
@ the terms of the GNU Lesser General Public License as published by the Free
@ Software Foundation, either version 3 of the License, or (at your option) any
@ later version.
@
@ This program is distributed in the hope that it will be useful, but WITHOUT
@ ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
@ FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more
@ details.
@
@ You should have received a copy of the GNU Lesser General Public License
@ along with this program.  If not, see <http://www.gnu.org/licenses/>.
@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

        .set JONES_VERSION,47
        #include <asm/unistd.h>

@ Reserve three special registers:
@ DSP (r13) points to the top of the data stack
@ RSP (r11) points to the top of the return stack
@ IP (r10) points to the next forth word that will be executed

        #define DSP r13
        #define RSP r11
        #define IP r10

@ Define stdin, stdout, stderr file descriptors numbers

        .set stdin, 0
        .set stdout, 1
        .set stderr, 2

@ Implement NEXT, which:
@   1. finds the address of the forth word to execute by
@      dereferencing the IP
@   2. increment IP
@   3. executes the forth word

        .macro NEXT
        ldr r0, [IP], #4
        ldr r1, [r0]
        bx r1
        .endm

@ Define macros to push and pop from the data
@ and return stacks

        .macro PUSHRSP reg
        str \reg, [RSP, #-4]!
        .endm

        .macro POPRSP reg
        ldr \reg, [RSP], #4
        .endm

        .macro push reg
        str \reg, [DSP, #-4]!
        .endm

        .macro pop reg
        ldr \reg, [DSP], #4
        .endm

@ DOCOL is the assembly subroutine that is called
@ at the start of every forth word execution.
@ It saves the old IP on the return stack, and
@ makes IP point to the first codeword.
@ Then it calls NEXT to start interpreting the word.

        .text
        .align 2
DOCOL:
        PUSHRSP IP
        add IP, r0, #4
        NEXT

@ _start is the program entry point

        .text
        .align 2
        .global _start
_start:
        ldr r0, =var_S0
        str DSP, [r0]           @ Save the original stack position in var_S0
        ldr RSP, =return_stack_top      @ Set the initial return stack position
        bl  set_up_data_segment         @ Set up the data segment
        ldr IP, =cold_start             @ Make the IP point to cold_start
        NEXT                            @ Start the interpreter


@ Allocate a data segment to define new words and data
@ structures

        .set INITIAL_DATA_SEGMENT_SIZE,65536
        .text
        .align 2

set_up_data_segment:

        mov r1, #0
        mov r7, #__NR_brk
        swi 0                   @ Call brk(0) to get value of Program Break

        ldr r1, =var_HERE
        str r0, [r1]            @ Initialize HERE to point at the beginning
                                @ of data segment

        add r0, #INITIAL_DATA_SEGMENT_SIZE
        swi 0                   @ Allocate Memory

        bx      lr              @ Return

@ cold_start is used to bootstrap the interpreter, the first word executed
@ is QUIT

        .section .rodata
cold_start:
        .int QUIT

@@ Now we define a set of helper macros that are syntactic sugar
@@ to ease the declaration of Forth words, Native words, Forth variables
@@ and Forth constants.

@ define the word flags
        .set F_IMMED,0x80
        .set F_HIDDEN,0x20
        .set F_LENMASK,0x1f

@ link is used to chain the words in the dictionary as they are defined
        .set link,0

@ defword macro helps defining new forth words in assembly

        .macro defword name, namelen, flags=0, label
        .section .rodata
        .align 2
        .global name_\label
name_\label :
        .int link               @ link
        .set link,name_\label
        .byte \flags+\namelen   @ flags + length byte
        .ascii "\name"          @ the name
        .align 2                @ padding to next 4 byte boundary
        .global \label
\label :
        .int DOCOL              @ codeword - the interpreter
        @ list of word pointers follow
        .endm

@ defcode macro helps defining new native words in assembly

        .macro defcode name, namelen, flags=0, label
        .section .rodata
        .align 2
        .globl name_\label
name_\label :
        .int link               @ link
        .set link,name_\label
        .byte \flags+\namelen   @ flags + length byte
        .ascii "\name"          @ the name
        .align 2                @ padding to next 4 byte boundary
        .global \label
\label :
        .int code_\label        @ codeword
        .text
        .global code_\label
code_\label :                   @ assembler code follows
        .endm

@ defvar macro helps defining Forth variables in assembly

        .macro defvar name, namelen, flags=0, label, initial=0
        defcode \name,\namelen,\flags,\label
        ldr r0, =var_\name
        push r0
        NEXT
        .data
        .align 2
var_\name :
        .int \initial
        .endm

@defconst macro helps defining Forth constants in assembly

        .macro defconst name, namelen, flags=0, label, value
        defcode \name,\namelen,\flags,\label
        ldr r0, =\value
        push r0
        NEXT
        .endm

@ EXIT is the last codeword of a forth word.
@ It restores the IP and returns to the caller using NEXT.
@ (See DOCOL)

defcode "EXIT",4,,EXIT
        POPRSP IP
        NEXT

@ DIVMOD computes the unsigned integer division and remainder
@ The implementation is based upon the algorithm extracted from 'ARM Software
@ Development Toolkit User Guide v2.50' published by ARM in 1997-1998
@ The algorithm is split in two steps: search the biggest divisor b^(2^n)
@ lesser than a and then subtract it and all b^(2^i) (for i from 0 to n)
@ to a.
@ ( a b -- r q ) where a = q * b + r

defcode "/MOD",4,,DIVMOD
        pop     r1                      @ Get b
        pop     r0                      @ Get a
        mov     r3, r1                  @ Put b in tmp

        cmp     r3, r0, LSR #1
1:      movls   r3, r3, LSL #1          @ Double tmp
        cmp     r3, r0, LSR #1
        bls     1b                      @ Jump until 2 * tmp > a

        mov     r2, #0                  @ Initialize q

2:      cmp     r0, r3                  @ If a - tmp > 0
        subcs   r0, r0, r3              @ a <= a - tmp
        adc     r2, r2, r2              @ Increment q
        mov     r3, r3, LSR #1          @ Halve tmp
        cmp     r3, r1                  @ Jump until tmp < b
        bhs     2b

        push    r0                      @ Put r
        push    r2                      @ Put q
        NEXT

@ Alternative to DIVMOD: signed implementation using Euclidean division.
defcode "S/MOD",5,,SDIVMOD
        @ Denominator
        pop r2
        @ Numerator
        pop r1

        bl _DIVMOD

        @ Remainder
        push r1
        @ Quotient
        push r0

        NEXT

_DIVMOD:
        @ Division by 0.
        cmp r2, #0
        beq 4f

        @ r0 will store the quotient at the end.
        mov r0, #0

        @ r3 will be 1 if numerator and denominator have the same
        @ sign, -1 otherwise.
        @ r4 will be 1 if the numerator is positive, -1 otherwise.
        mov r3, #1
        mov r4, #1

        rsblt r3, r3, #0 @ r3 = -r3 if negative denominator
        rsblt r2, r2, #0 @ denominator = abs(denominator)

        cmp r1, #0
        rsblt r4, r4, #0 @ r4 = sign(numerator)
        rsblt r3, r3, #0 @ r3 = -r3 if negative numerator
        rsblt r1, r1, #0 @ numerator = abs(numerator)

        cmp r3, #-1
        beq 2f

1:      @ Case where denominator and numerator have the same sign.
        cmp r1, r2
        blt 3f
        11:
        add r0, r0, #1
        sub r1, r1, r2
        cmp r1, r2
        bge 11b

        b 3f

2:      @ Case where denominator and numerator have different sign.
        cmp r1, #0
        beq 3f
        21:
        sub r0, r0, #1
        sub r1, r1, r2
        cmp r1, #0
        bgt 21b

3:
        @ If numerator and denominator were negative:
        @ remainder = -remainder
        cmp r4, #-1
        rsbeq r1, r1, #0
        b 5f

4:      @ Error, division by 0.
        # Display error message on stderr.
        mov r0, #stderr
        ldr r1, =div0msg
        mov r2, #div0msgend-div0msg
        mov r7, #__NR_write
        swi 0

5:
        bx lr

.section .rodata
div0msg: .ascii "Division by 0!\n"
div0msgend:

@ DROP ( a -- ) drops the top element of the stack

defcode "DROP",4,,DROP
        pop r0 @( )
        NEXT

@ SWAP ( a b -- b a ) swaps the two top elements

defcode "SWAP",4,,SWAP
        @ ( a b -- )
        pop r0          @  ( a ) , r0 = b
        pop r1          @  (  ) , r0 = b, r1 = a
        push r0         @  ( b  ) , r0 = b, r1 = a
        push r1         @  ( b a  ) , r0 = b, r1 = a
        NEXT

@ DUP ( a -- a a ) duplicates the top element

defcode "DUP",3,,DUP
        @ ( a -- )
        pop r0          @ (  ) , r0 = a
        push r0         @ ( a  ) , r0 = a
        push r0         @ ( a a  ) , r0 = a
        NEXT

@ OVER ( a b c -- a b c b ) pushes the second element on top

defcode "OVER",4,,OVER
        @ ( a b c) r0 = b we take the element at DSP + 4
        @ and since DSP is the top of the stack we will load
        @ the second element of the stack in r0
        ldr r0, [DSP, #4]
        push r0         @ ( a b c b )
        NEXT

@ ROT ( a b c -- b c a) rotation

defcode "ROT",3,,ROT
        pop r0          @ ( a b ) r0 = c
        pop r1          @ ( a ) r1 = b
        pop r2          @ ( ) r2 = a
        push r1         @ ( b )
        push r0         @ ( b c )
        push r2         @ ( b c a )
        NEXT

@ -ROT ( a b c -- c a b ) backwards rotation

defcode "-ROT",4,,NROT
        pop r0          @ ( a b ) r0 = c
        pop r1          @ ( a ) r1 = b
        pop r2          @ ( ) r2 = a
        push r0         @ ( c )
        push r2         @ ( c a )
        push r1         @ ( c a b )
        NEXT

@ ?DUP ( 0 -- 0 | a -- a a ) duplicates if non-zero

defcode "?DUP", 4,,QDUP
        @ (x --)
        ldr r0, [DSP]   @ r0 = x
        cmp r0, #0      @ test if x==0
        beq 1f          @ if x==0 we jump to 1
        push r0         @ ( a a ) it's now duplicated
        1: NEXT         @ ( a a / 0 )

@ 1+ ( a | a+1 ) increments the top element

defcode "1+",2,,INCR
        pop r0
        add r0,r0,#1
        push r0
        NEXT

@ 1- ( a | a-1 ) decrements the top element

defcode "1-",2,,DECR
        pop r0
        sub r0,r0,#1
        push r0
        NEXT

@ 4+ ( a | a+4 ) increments by 4 the top element

defcode "4+",2,,INCR4
        pop r0
        add r0,r0,#4
        push r0
        NEXT

@ 4- ( a | a-4 ) decrements by 4 the top element

defcode "4-",2,,DECR4
        pop r0
        sub r0,r0,#4
        push r0
        NEXT

@ + ( a b | a+b)

defcode "+",1,,ADD
        pop r0
        pop r1
        add r0,r0,r1
        push r0
        NEXT

@ + ( a b | a-b)

defcode "-",1,,SUB
        pop r1
        pop r0
        sub r0,r0,r1
        push r0
        NEXT

@ + ( a b | a*b)

defcode "*",1,,MUL
        pop r0
        pop r1
        mul r2,r0,r1
        push r2
        NEXT

@ = ( a b | p ) where p is 1 when a and b are equal (0 otherwise)

defcode "=",1,,EQU
        pop r1
        pop r0
        cmp r0, r1
        moveq r0, #1
        movne r0, #0
        push r0
        NEXT

@ <> ( a b | p) where p = a <> b

defcode "<>",2,,NEQU
        pop r1
        pop r0
        cmp r0, r1
        movne r0, #1
        moveq r0, #0
        push r0
        NEXT

@ < ( a b | p) where p = a < b

defcode "<",1,,LT
        pop r1
        pop r0
        cmp r0, r1
        movlt r0, #1
        movge r0, #0
        push r0
        NEXT

@ < ( a b | p) where p = a < b

defcode ">",1,,GT
        pop r1
        pop r0
        cmp r0, r1
        movgt r0, #1
        movle r0, #0
        push r0
        NEXT

@ <= ( a b | p) where p = a <= b

defcode "<=",2,,LE
        pop r1
        pop r0
        cmp r0, r1
        movle r0, #1
        movgt r0, #0
        push r0
        NEXT

@ >= ( a b | p) where p = a >= b

defcode ">=",2,,GE
        pop r1
        pop r0
        cmp r0, r1
        movge r0, #1
        movlt r0, #0
        push r0
        NEXT

@ AND ( a b | a&b) bitwise and

defcode "AND",3,,AND
        pop r0
        pop r1
        and r0, r1, r0
        push r0
        NEXT

@ OR ( a b | a|b) bitwise or

defcode "OR",2,,OR
        pop r0
        pop r1
        orr r0, r1, r0
        push r0
        NEXT

@ XOR ( a b | a^b) bitwise xor

defcode "XOR",3,,XOR
        pop r0
        pop r1
        eor r0, r1, r0
        push r0
        NEXT

@ INVERT ( a | ~a ) bitwise not

defcode "INVERT",6,,INVERT
        pop r0
        mvn r0, r0
        push r0
        NEXT



@ LIT is used to compile literals in forth word.
@ When LIT is executed it pushes the literal (which is the next codeword)
@ into the stack and skips it (since the literal is not executable).

defcode "LIT", 3,, LIT
        ldr r1, [IP], #4
        push r1
        NEXT

@ ! ( value address -- ) write value at address

defcode "!",1,,STORE
        pop r0
        pop r1
        str r1, [r0]
        NEXT

@ @ ( address -- value ) reads value from address

defcode "@",1,,FETCH
        pop r1
        ldr r0, [r1]
        push r0
        NEXT

@ C! and @! are the same for bytes

defcode "C!",2,,STOREBYTE
        pop r0
        pop r1
        strb r1, [r0]
        NEXT


defcode "C@",2,,FETCHBYTE
        pop r0
        mov r1, #0
        ldrb r1, [r0]
        push r1
        NEXT



@ CMOVE ( source dest length -- ) copies a chunk of length bytes from source
@ address to dest address

defcode "CMOVE",5,,CMOVE
        pop r0
        pop r1
        pop r2
1:
        cmp r0, #0              @ while length > 0
        ldrgtb r3, [r2], #1     @ read character from source
        strgtb r3, [r1], #1     @ and write it to dest (increment both pointers)
        subgt r0, r0, #1        @ decrement length
        bgt 1b
        NEXT


@ Define some variables and constants needed by the Forth interpreter

        defvar "STATE",5,,STATE
        defvar "HERE",4,,HERE
        defvar "LATEST",6,,LATEST,name_SYSCALL0 @ must point to the last word
                                                @ defined in assembly, SYSCALL0
        defvar "S0",2,,SZ
        defvar "BASE",4,,BASE,10

        defconst "VERSION",7,,VERSION,JONES_VERSION
        defconst "R0",2,,RZ,return_stack_top
        defconst "DOCOL",5,,__DOCOL,DOCOL
        defconst "F_IMMED",7,,__F_IMMED,F_IMMED
        defconst "F_HIDDEN",8,,__F_HIDDEN,F_HIDDEN
        defconst "F_LENMASK",9,,__F_LENMASK,F_LENMASK

        defconst "SYS_EXIT",8,,SYS_EXIT,__NR_exit
        defconst "SYS_OPEN",8,,SYS_OPEN,__NR_open
        defconst "SYS_CLOSE",9,,SYS_CLOSE,__NR_close
        defconst "SYS_READ",8,,SYS_READ,__NR_read
        defconst "SYS_WRITE",9,,SYS_WRITE,__NR_write
        defconst "SYS_CREAT",9,,SYS_CREAT,__NR_creat
        defconst "SYS_BRK",7,,SYS_BRK,__NR_brk

        defconst "O_RDONLY",8,,__O_RDONLY,0
        defconst "O_WRONLY",8,,__O_WRONLY,1
        defconst "O_RDWR",6,,__O_RDWR,2
        defconst "O_CREAT",7,,__O_CREAT,0100
        defconst "O_EXCL",6,,__O_EXCL,0200
        defconst "O_TRUNC",7,,__O_TRUNC,01000
        defconst "O_APPEND",8,,__O_APPEND,02000
        defconst "O_NONBLOCK",10,,__O_NONBLOCK,04000


@ >R ( a -- ) move the top element from the data stack to the return stack

defcode ">R",2,,TOR
        pop r0
        PUSHRSP r0
        NEXT

@ R> ( -- a ) move the top element from the return stack to the data stack

defcode "R>",2,,FROMR
        POPRSP r0
        push r0
        NEXT

@ RDROP drops the top element from the return stack

defcode "RDROP",5,,RDROP
        add RSP,RSP,#4
        NEXT

@ RSP@, RSP!, DSP@, DSP! manipulate the return and data stack pointers

defcode "RSP@",4,,RSPFETCH
        push RSP
        NEXT

defcode "RSP!",4,,RSPSTORE
        pop RSP
        NEXT

defcode "DSP@",4,,DSPFETCH
        mov r0, DSP
        push r0
        NEXT

defcode "DSP!",4,,DSPSTORE
        pop r0
        mov r0, DSP
        NEXT

@ KEY ( -- c ) Reads a key from the user
@ the implementation uses a cached buffer that is
@ refilled, when empty, with a read syscall.

defcode "KEY",3,,KEY

        bl _KEY                 @ Call _KEY
        push r0                 @ push the return value on the stack
        NEXT

_KEY:

        ldr r3, =currkey        @ Load the address of currkey
        ldr r1, [r3]            @ Get the value of currkey
        ldr r3, =bufftop        @ Load the address of bufftop
        ldr r2, [r3]            @ Get the value of bufftop
        cmp r2, r1
        ble 1f                  @ if bufftop <= currkey

        ldrb r0, [r1]           @ load the first byte of currkey
        ldr r3, =currkey
        add r1, #1              @ Increments CURRKEY
        str r1, [r3]

        bx lr                   @ return

1:
        ldr r3, =currkey
        mov r0, #0              @ 1st arg: STDIN
        ldr r1, =buffer         @ 2nd arg : buffer add
        str r1, [r3]            @ CURRKEY := BUFFER
        mov r2, #BUFFER_SIZE    @ 3rd arg : buffer sz
        mov r7, #__NR_read      @ read syscall flag
        swi 0                   @ call
        cmp r0, #0
        ble 2f                  @ if errors goto 2
        add r1,r0               @ Set bufftop at the end of the word
        ldr r4, =bufftop
        str r1, [r4]            @ update bufftop
        b       _KEY

2:                              @ read syscall returned with an error
        mov r0, #0
        mov r7, #__NR_exit      @ exit(0)
        swi 0


@ buffer for KEY

        .data
        .align 2
currkey:
        .int buffer
bufftop:
        .int buffer

@ EMIT ( c -- ) outputs character c to stdout

defcode "EMIT",4,,EMIT
        pop r0
        bl      _EMIT
        NEXT

_EMIT:
        ldr r2, =emit_scratch
        str r0, [r2]            @ write character to memory
        mov r1, r2
        mov r2, #1              @ write 1 byte
        mov r0, #stdout         @ write on standard output
        mov r7, #__NR_write     @ write syscall flag

        swi 0                   @ write syscall
        bx lr


        .data
emit_scratch:
        .space 1

@ WORD ( -- addr length ) reads next word from stdin
@ skips spaces and comments, limited to 32 characters

defcode "WORD",4,,WORD
        bl _WORD
        push r0                 @ adress
        push r1                 @ length
        NEXT

_WORD:
        stmfd   sp!, {r6,lr}    @ preserve r6 and lr
1:
        bl _KEY                 @ read a character
        cmp r0, #'\\'
        beq 3f                  @ skip comments until end of line
        cmp r0, #' '
        ble 1b                  @ skip blank character

        ldr     r6, =word_buffer
2:
        strb r0, [r6], #1       @ store character in word buffer
        bl _KEY                 @ read more characters until a space is found
        cmp r0, #' '
        bgt 2b

        ldr r0, =word_buffer    @ r0, address of word
        sub r1, r6, r0          @ r1, length of word

        ldmfd sp!, {r6,lr}      @ restore r6 and lr
        bx lr
3:
        bl _KEY                 @ skip all characters until end of line
        cmp r0, #'\n'
        bne 3b
        b 1b

@ word_buffer for WORD

        .data
word_buffer:
        .space 32

@ NUMBER ( addr length -- n e ) converts string to number
@ n is the parsed number
@ e is the number of unparsed characters

defcode "NUMBER",6,,NUMBER
        pop r1
        pop r0
        bl _NUMBER
        push r0
        push r1
        NEXT

_NUMBER:
        stmfd sp!, {r4-r6, lr}

        @ Save address of the string.
        mov r2, r0

        @ r0 will store the result after conversion.
        mov r0, #0

        @ Check if length is positive, otherwise this is an error.
        cmp r1, #0
        ble 5f

        @ Load current base.
        ldr r3, =var_BASE
        ldr r3, [r3]

        @ Load first character and increment pointer.
        ldrb r4, [r2], #1

        @ Check trailing '-'.
        mov r5, #0
        cmp r4, #45 @ 45 in '-' en ASCII
        @ Number is positive.
        bne 2f
        @ Number is negative.
        mov r5, #1
        sub r1, r1, #1

        @ Check if we have more than just '-' in the string.
        cmp r1, #0
        @ No, proceed with conversion.
        bgt 1f
        @ Error.
        mov r1, #1
        b 5f
1:
        @ number *= BASE
        @ Arithmetic shift right.
        @ On ARM we need to use an additional register for MUL.
        mul r6, r0, r3
        mov r0, r6

        @ Load the next character.
        ldrb r4, [r2], #1
2:
        @ Convert the character into a digit.
        sub r4, r4, #48 @ r4 = r4 - '0'
        cmp r4, #0
        blt 4f @ End, < 0
        cmp r4, #9
        ble 3f @ chiffre compris entre 0 et 9

        @ Test if hexadecimal character.
        sub r4, r4, #17 @ 17 = 'A' - '0'
        cmp r4, #0
        blt 4f @ End, < 'A'
        add r4, r4, #10
3:
        @ Compare to the current base.
        cmp r4, r3
        bge 4f @ End, > BASE

        @ Everything is fine.
        @ Add the digit to the result.
        add r0, r0, r4
        sub r1, r1, #1

        @ Continue processing while there are still characters to read.
        cmp r1, #0
        bgt 1b
4:
        @ Negate result if we had a '-'.
        cmp r5, #1
        rsbeq r0, r0, #0
5:
        @ Back to the caller.
        ldmfd sp!, {r4-r6, pc}


@ FIND ( addr length -- dictionary_address )
@ Tries to find a word in the dictionary and returns its address.
@ If the word is not found, NULL is returned.

defcode "FIND",4,,FIND
    pop r1 @length
    pop r0 @addr
        bl _FIND
        push r0
        NEXT

_FIND:
        stmfd   sp!, {r5,r6,r8,r9}      @ save callee save registers
        ldr r2, =var_LATEST
        ldr r3, [r2]                    @ get the last defined word address
1:
        cmp r3, #0                      @ did we check all the words ?
        beq 4f                          @ then exit

        ldrb r2, [r3, #4]               @ read the length field
        and r2, r2, #(F_HIDDEN|F_LENMASK) @ keep only length + hidden bits
        cmp r2, r1                      @ do the lengths match ?
                                        @ (note that if a word is hidden,
                                        @  the test will be always negative)
        bne 3f                          @ branch if they do not match
                                        @ Now we compare strings characters
        mov r5, r0                      @ r5 contains searched string
        mov r6, r3                      @ r6 contains dict string
        add r6, r6, #5                  @ (we skip link and length fields)
                                        @ r2 contains the length

2:
        ldrb r8, [r5], #1               @ compare character per character
        ldrb r9, [r6], #1
        cmp r8,r9
        bne 3f                          @ if they do not match, branch to 3
        subs r2,r2,#1                   @ decrement length
        bne 2b                          @ loop

                                        @ here, strings are equal
        b 4f                            @ branch to 4

3:
        ldr r3, [r3]                    @ Mismatch, follow link to the next
        b 1b                            @ dictionary word
4:
        mov r0, r3                      @ move result to r0
        ldmfd   sp!, {r5,r6,r8,r9}      @ restore callee save registers
        bx lr

@ >CFA ( dictionary_address -- executable_address )
@ Transformat a dictionary address into a code field address

defcode ">CFA",4,,TCFA
        pop r0
        bl _TCFA
        push r0
        NEXT
_TCFA:
        add r0,r0,#4            @ skip link field
        ldrb r1, [r0], #1       @ load and skip the length field
        and r1,r1,#F_LENMASK    @ keep only the length
        add r0,r0,r1            @ skip the name field
        add r0,r0,#3            @ find the next 4-byte boundary
        and r0,r0,#~3
        bx lr

@ >DFA ( dictionary_address -- data_field_address )
@ Return the address of the first data field

defword ">DFA",4,,TDFA
        .int TCFA
        .int INCR4
        .int EXIT


@ CREATE ( address length -- ) Creates a new dictionary entry
@ in the data segment.
@ CREATE ( address length -- ) Creates a new dictionary entry
@ in the data segment.

defcode "CREATE",6,,CREATE

        pop r1          @ length of the word to insert into the dictionnary
        pop r0          @ address of the word to insert into the dictionnary

        ldr r2,=var_HERE
        ldr r3,[r2]     @ load into r3 and r8 the location of the header
        mov r8,r3

        ldr r4,=var_LATEST
        ldr r5,[r4]     @ load into r5 the link pointer

        str r5,[r3]     @ store link here -> last

        add r3,r3,#4    @ skip link adress
        strb r1,[r3]    @ store the length of the word
        add r3,r3,#1    @ skip the length adress

        mov r7,#0       @ initialize the incrementation

1:
        cmp r7,r1       @ if the word is completley read
        beq 2f

        ldrb r6,[r0,r7] @ read and store a character
        strb r6,[r3,r7]

        add r7,r7,#1    @ ready to rad the next character

        b 1b

2:

        add r3,r3,r7            @ skip the word

        add r3,r3,#3            @ align to next 4 byte boundary
        and r3,r3,#~3

        str r8,[r4]             @ update LATEST and HERE
        str r3,[r2]

        NEXT

@ , ( n -- ) writes the top element from the stack at HERE

defcode ",",1,,COMMA
        pop r0
        bl _COMMA
        NEXT
_COMMA:
        ldr     r1, =var_HERE
        ldr     r2, [r1]        @ read HERE
        str     r0, [r2], #4    @ write value and increment address
        str     r2, [r1]        @ update HERE
        bx      lr

@ [ ( -- ) Change interpreter state to Immediate mode

defcode "[",1,F_IMMED,LBRAC
        ldr     r0, =var_STATE
        mov     r1, #0
        str     r1, [r0]
        NEXT

@ ] ( -- ) Change interpreter state to Compilation mode

defcode "]",1,,RBRAC
        ldr     r0, =var_STATE
        mov     r1, #1
        str     r1, [r0]
        NEXT

@ : ( -- ) Define a new forth word

defword ":",1,,COLON
        .int WORD                       @ Get the name of the new word
        .int CREATE                     @ CREATE the dictionary entry / header
        .int LIT, DOCOL, COMMA          @ Append DOCOL  (the codeword).
        .int LATEST, FETCH, HIDDEN      @ Make the word hidden
                                        @ (see below for definition).
        .int RBRAC                      @ Go into compile mode.
        .int EXIT                       @ Return from the function.

defword ";",1,F_IMMED,SEMICOLON
        .int LIT, EXIT, COMMA           @ Append EXIT (so the word will return).
        .int LATEST, FETCH, HIDDEN      @ Toggle hidden flag -- unhide the word
                                        @ (see below for definition).
        .int LBRAC                      @ Go back to IMMEDIATE mode.
        .int EXIT                       @ Return from the function.

@ IMMEDIATE ( -- ) sets IMMEDIATE flag of last defined word

defcode "IMMEDIATE",9,F_IMMED,IMMEDIATE
        ldr r0, =var_LATEST     @
        ldr r1, [r0]            @ get the Last word
        add r1, r1, #4          @ points to the flag byte
                                @
        mov r2, #0              @
        ldrb r2, [r1]           @ load the flag into r2
                                @
        eor r2, r2, #F_IMMED    @ r2 = r2 xor F_IMMED
        strb r2, [r1]           @ update the flag
        NEXT

@ HIDDEN ( dictionary_address -- ) sets HIDDEN flag of a word

defcode "HIDDEN",6,,HIDDEN
        pop  r0
        ldr r1, [r0, #4]!
        eor r1, r1, #F_HIDDEN
        str r1, [r0]
        NEXT

@ HIDE ( -- ) hide a word

defword "HIDE",4,,HIDE
        .int WORD               @ Get the word (after HIDE).
        .int FIND               @ Look up in the dictionary.
        .int HIDDEN             @ Set F_HIDDEN flag.
        .int EXIT               @ Return.

@ TICK ( -- ) returns the codeword address of next read word
@ only works in compile mode. Implementation is identical to LIT.

defcode "'",1,,TICK
        ldr r1, [IP], #4
        push r1
        NEXT

@ BRANCH ( -- ) changes IP by offset which is found in the next codeword

defcode "BRANCH",6,,BRANCH
        ldr r1, [IP]
        add IP, IP, r1
        NEXT

@ 0BRANCH ( p -- ) branch if the top of the stack is zero

defcode "0BRANCH",7,,ZBRANCH
        pop r0
        cmp r0, #0              @ if the top of the stack is zero
        beq code_BRANCH         @ then branch
        add IP, IP, #4          @ else, skip the offset
        NEXT

@ LITSTRING ( -- ) as LIT but for strings

defcode "LITSTRING",9,,LITSTRING
        ldr r0, [IP], #4        @ read length
        push IP                 @ push address
        push r0                 @ push string
        add IP, IP, r0          @ skip the string
        add IP, IP, #3          @ find the next 4-byte boundary
        and IP, IP, #~3
        NEXT

@ TELL ( addr length -- ) writes a string to stdout

defcode "TELL",4,,TELL
        mov r0, #stdout
        pop r2 @length
        pop r1 @addr
        ldr r7, =__NR_write
        swi 0
        NEXT

@ QUIT ( -- ) the first word to be executed

defword "QUIT", 4,, QUIT
        .int RZ, RSPSTORE       @ Set up return stack
        .int INTERPRET          @ Interpret a word
        .int BRANCH,-8          @ loop

@ INTERPRET, reads a word from stdin and executes or compiles it

defcode "INTERPRET",9,,INTERPRET
    @ No need to backup callee save registers here, since
    @ we are the top level routine

        mov r8, #0                      @ interpret_is_lit = 0

        bl _WORD                        @ read a word from stdin
        mov r4, r0                      @ store it in r4,r5
        mov r5, r1

        bl _FIND                        @ find its dictionary entry
        cmp r0, #0                      @ if not found go to 1
        beq 1f

    @ Here the entry is found
        ldrb r6, [r0, #4]               @ read length and flags field
        bl _TCFA                        @ find code field address
        tst r6, #F_IMMED                @ if the word is immediate
        bne 4f                          @ branch to 6 (execute)
        b 2f                            @ otherwise, branch to 2

1:  @ Not found in dictionary
        mov r8, #1                      @ interpret_is_lit = 1
        mov r0, r4                      @ restore word
        mov r1, r5
        bl _NUMBER                      @ convert it to number
        cmp r1, #0                      @ if errors were found
        bne 6f                          @ then fail

    @ it's a literal
        mov r6, r0                      @ keep the parsed number if r6
        ldr r0, =LIT                    @ we will compile a LIT codeword

2:  @ Compiling or Executing
        ldr r1, =var_STATE              @ Are we compiling or executing ?
        ldr r1, [r1]
        cmp r1, #0
        beq 4f                          @ Go to 4 if in interpret mode

    @ Here in compile mode

        bl _COMMA                       @ Call comma to compile the codeword
        cmp r8,#1                       @ If it's a literal, we have to compile
        moveq r0,r6                     @ the integer ...
        bleq _COMMA                     @ .. too
        NEXT

4:  @ Executing
        cmp r8,#1                       @ if it's a literal, branch to 5
        beq 5f

                                        @ not a literal, execute now
        ldr r1, [r0]                    @ (it's important here that
        bx r1                           @  IP address in r0, since DOCOL
                                        @  assummes it)

5:  @ Push literal on the stack
        push r6
        NEXT

6:  @ Parse error
        mov r0, #stderr                 @ Write an error message
        ldr r1, =errmsg
        mov r2, #(errmsgend-errmsg)
        ldr r7, =__NR_write
        swi 0

        mov r0, #stderr                 @ with the word that could not be parsed
        mov r1, r4
        mov r2, r5
        ldr r7, =__NR_write
        swi 0

        mov r0, #stderr
        ldr r1, =errmsg2
        mov r2, #(errmsg2end-errmsg2)
        ldr r7, =__NR_write
        swi 0

        NEXT

        .section .rodata
errmsg: .ascii "PARSE ERROR<"
errmsgend:

errmsg2: .ascii ">\n"
errmsg2end:

@ CHAR ( -- c ) put the ASCII code of the first character of the next word
@ on the stack

defcode "CHAR",4,,CHAR
        bl _WORD
        ldrb r1, [r0]
        push r1
        NEXT

@ EXECUTE ( xt -- ) jump to the address on the stack

defcode "EXECUTE",7,,EXECUTE
        pop r0
        ldr r1, [r0]
        bx r1

@ Wrappers for doing syscalls from the forth word
@ SYSCALLX have to be used for a syscall with X arguments
@ In ARM, syscalls arguments must be located in r0-r2 and
@ the syscall index is in r7.
@ The return value is then pushed in the stack.
@ SYSCALLX ( i [arg1 arg2 ar3] -- r )

defcode "SYSCALL3",8,,SYSCALL3
        pop r7
        pop r0
        pop r1
        pop r2
        swi 0
        push r0
        NEXT

defcode "SYSCALL2",8,,SYSCALL2
        pop r7
        pop r0
        pop r1
        swi 0
        push r0
        NEXT

defcode "SYSCALL1",8,,SYSCALL1
        pop r7
        pop r0
        swi 0
        push r0
        NEXT

defcode "SYSCALL0",8,,SYSCALL0
        pop r7
        swi 0
        push r0
        NEXT

@ Reserve space for the return stack and the read buffer (for KEY)

        .bss

        .set RETURN_STACK_SIZE,8192
        .set BUFFER_SIZE,4096

        .align 12
return_stack:
        .space RETURN_STACK_SIZE
return_stack_top:

        .align 12
buffer:
        .space BUFFER_SIZE
