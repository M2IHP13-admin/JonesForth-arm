@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Jones' Forth port for ARM EABI
@
@ Original x86 and forth code: Richard W.M. Jones
@ <rich@annexia.org>
@
@
@ The extensive comments from Jones' x86 version have been
@ removed.  You should check them out, they are really
@ detailed, well written and pedagogical.
@
@ Some code is borrowed from the ARM port from
@ Peter H. Froehlich <phf@acm.org>
@
@ The DIVMOD routine is taken from the ARM Software
@ Development Toolkit User Guide 2.50.
@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

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

	.macro PUSHRSP reg	@ *push an address contained in reg in the return stack*
	str \reg, [RSP, #-4]!	@ update the stack pointer and store the address
	.endm

	.macro POPRSP reg	@ *pop a address from the return stack to reg *
	ldr \reg, [RSP], #4	@ load the top address of the stack into reg and update the stack pointer
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
	str DSP, [r0]               @ Save the original stack position in var_S0
	ldr RSP, =return_stack_top  @ Set the initial return stack position
	bl  set_up_data_segment     @ Set up the data segment
	ldr IP, =cold_start         @ Make the IP point to cold_start
	NEXT                        @ Start the interpreter


@ Allocate a data segment to define new words and data
@ structures

	.set INITIAL_DATA_SEGMENT_SIZE,65536
	.text
    .align 2
set_up_data_segment:
	mov r0, #0
	ldr r7, =__NR_brk
	swi 0                       @ Call brk(0) syscall to get the end
	                            @ of the program memory segment
                                @ (which will be the start of the data segment)
    ldr r1, =var_HERE
	str r0, [r1]                @ Point var_HERE to the start of the data
                                @ segment
	add r0, r0, #INITIAL_DATA_SEGMENT_SIZE
	swi 0
	bx  lr                      @ Call brk(INITIAL_DATA_SEGMENT_SIZE)
                                @ to allocate memory for the data segment

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
	.int link		// link
	.set link,name_\label
	.byte \flags+\namelen	// flags + length byte
	.ascii "\name"		// the name
	.align 2		// padding to next 4 byte boundary
	.global \label
\label :
	.int DOCOL		// codeword - the interpreter
	// list of word pointers follow
	.endm

@ defcode macro helps defining new native words in assembly

	.macro defcode name, namelen, flags=0, label
	.section .rodata
	.align 2
	.globl name_\label
name_\label :
	.int link		// link
	.set link,name_\label
	.byte \flags+\namelen	// flags + length byte
	.ascii "\name"		// the name
	.align 2		// padding to next 4 byte boundary
	.global \label
\label :
	.int code_\label	// codeword
	.text
	.global code_\label
code_\label :			// assembler code follows
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
@ ( a b -- r q ) where a = q * b + r
@ Example from the ARM Software
@ Development Toolkit User Guide 2.50.
defcode "/MOD",4,,DIVMOD

	pop r2 @ b
	pop r1 @ a

   	mov	r3, r2            @ r3 = b
	cmp	r3, r1, LSR #1
1:	movls r3, r3, LSL #1  @ double r3
	cmp	r3, r1, LSR #1    @ until 2*r3 > a
	bls	1b

	mov	r0, #0            @ clear q
2:	cmp	r1, r3            @ if r3 < a
	subcs r1, r1,r3       @ a = a - r3
	adc	r0, r0, r0        @ double r0
	mov	r3, r3, LSR #1    @ halve r3
	cmp	r3, r2            @ loop until r3 < b
	bhs	2b

	push r1 @ remainder
	push r0 @ division
	NEXT


@ DROP ( a -- ) drops the top element of the stack

defcode "DROP",4,,DROP
	pop r0
	NEXT

@ SWAP ( a b -- b a ) swaps the two top elements

defcode "SWAP",4,,SWAP
	pop r0
	pop r1
	push r0
	push r1
	NEXT

@ DUP ( a -- a a ) duplicates the top element

defcode "DUP",3,,DUP
	pop r0
	push r0
	push r0
	NEXT

@ OVER ( a b c -- a b c b ) pushes the second element on top

defcode "OVER",4,,OVER
	ldr r0, [DSP, #4]
	push r0
	NEXT

@ ROT ( a b c -- b c a) rotation

defcode "ROT",3,,ROT
	pop r0
	pop r1
	pop r2
	push r1
	push r0
	push r2
	NEXT

@ -ROT ( a b c -- c a b ) backwards rotation

defcode "-ROT",4,,NROT
	pop r0
	pop r1
	pop r2
	push r0
	push r2
	push r1
	NEXT

@ ?DUP ( 0 -- 0 | a -- a a ) duplicates if non-zero

defcode "?DUP", 4,,QDUP
	ldr r0, [DSP]
	cmp r0, #0
	strne r0, [DSP, #-4]!
	NEXT

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
	pop	r1
	pop	r0
	cmp	r0, r1
	moveq	r0, #1
	movne	r0, #0
	push	r0
	NEXT

@ <> ( a b | p) where p = a <> b

defcode "<>",2,,NEQU
	pop	r1
	pop	r0
	cmp	r0, r1
	movne	r0, #1
	moveq	r0, #0
	push	r0
	NEXT

@ < ( a b | p) where p = a < b

defcode "<",1,,LT
	pop	r1
	pop	r0
	cmp	r0, r1
	movlt	r0, #1
	movge	r0, #0
	push	r0
	NEXT

@ < ( a b | p) where p = a < b

defcode ">",1,,GT
	pop	r1
	pop	r0
	cmp	r0, r1
	movgt	r0, #1
	movle	r0, #0
	push	r0
	NEXT

@ <= ( a b | p) where p = a <= b

defcode "<=",2,,LE
	pop	r1
	pop	r0
	cmp	r0, r1
	movle	r0, #1
	movgt	r0, #0
	push	r0
	NEXT

@ >= ( a b | p) where p = a >= b

defcode ">=",2,,GE
	pop	r1
	pop	r0
	cmp	r0, r1
	movge	r0, #1
	movlt	r0, #0
	push	r0
	NEXT

@ AND ( a b | a&b) bitwise and

defcode "AND",3,,AND
	pop	r0
	pop	r1
	and	r0, r1, r0
	push	r0
	NEXT

@ OR ( a b | a|b) bitwise or

defcode "OR",2,,OR
	pop	r0
	pop	r1
	orr	r0, r1, r0
	push	r0
	NEXT

@ XOR ( a b | a^b) bitwise xor

defcode "XOR",3,,XOR
	pop	r0
	pop	r1
	eor	r0, r1, r0
	push	r0
	NEXT

@ INVERT ( a | ~a ) bitwise not

defcode "INVERT",6,,INVERT
    pop r0
	mvn	r0, r0
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
	pop r0
	ldr r1, [r0]
	push r1
	NEXT

@ C! and @! are the same for bytes

defcode "C!",2,,STOREBYTE
	pop r0
	pop r1
	strb r1, [r0]
	NEXT

defcode "C@",2,,FETCHBYTE
	pop r0
	mov r1,#0
	ldrb r1,[r0]
	push r1
	NEXT

@ CMOVE ( source dest length -- ) copies a chunk of length bytes from source
@ address to dest address

defcode "CMOVE",5,,CMOVE
	pop	r0
	pop	r1
	pop	r2
1:
    cmp r0, #0           @ while length > 0
	ldrgtb r3, [r2], #1  @ read character from source
	strgtb r3, [r1], #1  @ and write it to dest (and increment both pointers)
	subgt r0, r0, #1     @ decrement length
	bgt	1b
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
	bl _KEY
	push r0
	NEXT

_KEY:
	ldr r2, =currkey
	ldr r1, [r2]          @ position of the last read key in the buffer
	ldr r0, =bufftop
	ldr r3, [r0]          @ buffer's limit
	cmp r1, r3            @ are there still keys in the buffer ?
	bge 1f                @ no, go refill
	ldrb r0, [r1], #1     @ yes, return key and increment
	str r1, [r2]          @ currkey
	bx lr
1:
	ldr r1, =buffer
	str r1, [r2]          @ reset currkey
	mov r0, #stdin
	ldr r2, =BUFFER_SIZE  @ refill buffer
	ldr r7, =__NR_read
	swi 0                 @ read(stdin, &buffer, BUFFER_SIZE)
	cmp r0,#0             @ check for errors ?
	ble 2f                @ if error, fail
	ldr r1, =buffer
	add r1,r1,r0
	ldr r2, =bufftop
	str r1, [r2]          @ update buffer limit
	b _KEY                @ return key to user

2:                        @ die if read error
	ldr r7,=__NR_exit
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
	bl _EMIT
	NEXT
_EMIT:
	ldr r1,=emit_scratch
	strb r0, [r1]         @ write character to memory
	mov r0,#stdout
	mov r2,#1
	ldr r7,=__NR_write
	swi 0                 @ call write(stdout, &emit_scratch)
	bx lr

	.data
emit_scratch:
	.space 1

@ WORD ( -- addr length ) reads next word from stdin
@ skips spaces and comments, limited to 32 characters

defcode "WORD",4,,WORD
	bl _WORD
	push r0 @adress
	push r1 @length
	NEXT

_WORD:
	stmfd	sp!, {r6,lr}   @ preserve r6 and lr
1:
	bl	_KEY               @ read a character
	cmp	r0, #'\\'
	beq	3f                 @ skip comments until end of line
	cmp	r0, #' '
	ble	1b                 @ skip blank character

	ldr	r6, =word_buffer
2:
	strb	r0, [r6], #1   @ store character in word buffer
	bl	_KEY               @ read more characters until a space is found
	cmp	r0, #' '
	bgt	2b

	ldr	r0, =word_buffer   @ r0, address of word
	sub	r1, r6, r0         @ r1, length of word

	ldmfd	sp!, {r6,lr}   @ restore r6 and lr
	bx	lr
3:
	bl	_KEY               @ skip all characters until end of line
	cmp	r0, #'\n'
	bne	3b
	b	1b

@ word_buffer for WORD

	.data
word_buffer:
	.space 32

@ NUMBER ( addr length -- n e ) converts string to number
@ n is the parsed number
@ e is the number of unparsed characters
@ Borrowed from the port of Peter H. Froehlich <phf@acm.org>

defcode "NUMBER",6,,NUMBER
	pop r1
	pop r0
	bl	_NUMBER
	push r0
	push r1
	NEXT

_NUMBER:
	stmfd	sp!, {r5,r6,r8,r9}

	mov	r2, r0		     @ address
	mov	r0, #0		     @ number
	cmp	r1, #0		     @ length <= 0?
	ble	5f		         @ really an error, but returns 0 anyway

	ldr	r5, =var_BASE
	ldr	r5, [r5]	     @ get BASE
	ldrb	r6, [r2], #1 @ get character and increment address
	mov	r9, #0		     @ set negative flag false
	cmp	r6, #'-'	     @ leading '-'?
	bne	2f		         @ nope, try to parse as digit

	mov	r9, #1		     @ set negative flag true
	subs	r1, r1, #1	 @ decrement length
	bpl	1f		         @ >0 so keep going

	mov	r1, #1		     @ just a sign, no digits, signal an error
	b	5f		         @ error!
1:
	mul	r8, r0, r5	     @ number = number * BASE
	mov	r0, r8		     @ (need to use another register for mul to avoid
                         @  warning)
	ldrb	r6, [r2], #1 @ get character and increment address
2:
	subs	r6, r6, #'0' @ try lower digit bound
	bmi	4f		         @ nope, < '0' so we're done
	cmp	r6, #10		     @ try upper digit bound
	blt	3f		         @ yes, we got one!
	subs	r6, r6, #17	 @ try lower char bound (17 is 'A'-'0')
	bmi	4f		         @ nope, < 'A' so we're done
	add	r6, r6, #10	     @ adjust for first 10 digit values before 'A'
3:
	cmp	r6, r5		     @ >= BASE?
	bge	4f		         @ yep, we're done

	                     @ finally, add new digit to number and loop
	add	r0, r6
	subs	r1, r1, #1
	bne	1b
4:
	cmp	r9, #1		     @ check negative flag
	rsbeq	r0, r0, #0	 @ yes, negate (r0 = 0 - r0)
5:
	ldmfd	sp!, {r5,r6,r8,r9}
	bx	lr


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
	stmfd	sp!, {r5,r6,r8,r9}        @ save callee save registers
	ldr r2, =var_LATEST
	ldr r3, [r2]                      @ get the last defined word address
1:
	cmp r3, #0                        @ did we check all the words ?
	beq 4f                            @ then exit

	ldrb r2, [r3, #4]                 @ read the length field
	and r2, r2, #(F_HIDDEN|F_LENMASK) @ keep only length + hidden bits
	cmp r2, r1                        @ do the lengths match ?
	                                  @ (note that if a word is hidden,
                                      @  the test will be always negative)
    bne 3f                            @ branch if they do not match

	                                  @ Now we compare strings characters
	mov r5, r0                        @ r5 contains searched string
	mov r6, r3                        @ r6 contains dict string
	add r6, r6, #5                    @ (we skip link and length fields)
                                      @ r2 contains the length

2:
	ldrb r8, [r5], #1                 @ compare character per character
	ldrb r9, [r6], #1
	cmp r8,r9
	bne 3f                            @ if they do not match, branch to 3
	subs r2,r2,#1                     @ decrement length
	bne 2b                            @ loop

	                                  @ here, strings are equal
	b 4f                              @ branch to 4

3:
	ldr r3, [r3]                      @ Mismatch, follow link to the next
	b 1b                              @ dictionary word
4:
	mov r0, r3                        @ move result to r0
	ldmfd	sp!, {r5,r6,r8,r9}        @ restore callee save registers
	bx lr

@ >CFA ( dictionary_address -- executable_address )
@ Transformat a dictionary address into a code field address

defcode ">CFA",4,,TCFA
	pop r0
	bl _TCFA
	push r0
	NEXT
_TCFA:
	add r0,r0,#4         @ skip link field
	ldrb r1, [r0], #1    @ load and skip the length field
	and r1,r1,#F_LENMASK @ keep only the length
	add r0,r0,r1         @ skip the name field
	add r0,r0,#3         @ find the next 4-byte boundary
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

defcode "CREATE",6,,CREATE
	pop r1             @ length
	pop r0             @ addr

	ldr r2,=var_HERE
	ldr r2,[r2]         @ load HERE address
	ldr r3,=var_LATEST
	ldr r3,[r3]         @ load LATEST address
	str r3,[r2],#4      @ create the link field
	strb r1,[r2],#1     @ create the length field

1:  ldrb r3, [r0], #1   @ copy the word name
	strb r3, [r2], #1
	sub r1, r1, #1      @ decrement length
	cmp r1, #0
	bgt 1b              @ loop

	add r2,r2,#3        @ pad to the next 4-byte boundary
	and r2,r2,#~3

	ldr r0, =var_HERE
	ldr r3, [r0]
	ldr r1, =var_LATEST @ update LATEST
	str r3, [r1]        @ LATEST <- old HERE
	str r2, [r0]        @ update HERE
	NEXT

@ , ( n -- ) writes the top element from the stack at HERE

defcode ",",1,,COMMA
	pop r0
	bl _COMMA
	NEXT
_COMMA:
	ldr	r1, =var_HERE
	ldr	r2, [r1]       @ read HERE
	str	r0, [r2], #4   @ write value and increment address
	str	r2, [r1]       @ update HERE
	bx	lr

@ [ ( -- ) Change interpreter state to Immediate mode

defcode "[",1,F_IMMED,LBRAC
	ldr	r0, =var_STATE
	mov	r1, #0
	str	r1, [r0]
	NEXT

@ ] ( -- ) Change interpreter state to Compilation mode

defcode "]",1,,RBRAC
	ldr	r0, =var_STATE
	mov	r1, #1
	str	r1, [r0]
	NEXT

@ : ( -- ) Define a new forth word

defword ":",1,,COLON
	.int WORD		           @ Get the name of the new word
	.int CREATE		           @ CREATE the dictionary entry / header
	.int LIT, DOCOL, COMMA	   @ Append DOCOL  (the codeword).
	.int LATEST, FETCH, HIDDEN @ Make the word hidden
                               @ (see below for definition).
	.int RBRAC		           @ Go into compile mode.
	.int EXIT		           @ Return from the function.

defword ";",1,F_IMMED,SEMICOLON
	.int LIT, EXIT, COMMA	   @ Append EXIT (so the word will return).
	.int LATEST, FETCH, HIDDEN @ Toggle hidden flag -- unhide the word
                               @ (see below for definition).
	.int LBRAC		           @ Go back to IMMEDIATE mode.
	.int EXIT		           @ Return from the function.

@ IMMEDIATE ( -- ) sets IMMEDIATE flag of last defined word

defcode "IMMEDIATE",9,F_IMMED,IMMEDIATE
	ldr r0, =var_LATEST     @ find last defined word
	ldr r2, [r0]
	ldrb r1, [r2, #4]!      @ read length and flags field
	eor r1, r1, #F_IMMED    @ set F_IMMED bit
	strb r1, [r2]           @ update the field
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
	.int WORD	        	@ Get the word (after HIDE).
	.int FIND	        	@ Look up in the dictionary.
	.int HIDDEN	        	@ Set F_HIDDEN flag.
	.int EXIT	        	@ Return.

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
	pop	r0
	cmp	r0, #0		 @ if the top of the stack is zero
	beq	code_BRANCH	 @ then branch
	add	IP, IP, #4   @ else, skip the offset
	NEXT

@ LITSTRING ( -- ) as LIT but for strings

defcode "LITSTRING",9,,LITSTRING
	ldr	r0, [IP], #4  @ read length
	push	IP	      @ push address
	push	r0	      @ push string
	add	IP, IP, r0    @ skip the string
	add	IP, IP, #3	  @ find the next 4-byte boundary
	and	IP, IP, #~3
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
	.int RZ, RSPSTORE    @ Set up return stack
	.int INTERPRET       @ Interpret a word
	.int BRANCH,-8       @ loop

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
	bl   _TCFA                      @ find code field address
	tst  r6, #F_IMMED               @ if the word is immediate
	bne 4f                          @ branch to 6 (execute)
	b   2f                          @ otherwise, branch to 2

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
