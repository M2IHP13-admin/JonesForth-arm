Jonesforth-ARM V 1.0 released Feb 20, 2013
An ARM port of X86 JonesForth by Richard W.M. Jones <rich@annexia.org>
http://annexia.org/forth

--------------------------------------------------------------------------------

Contributors: ABECASSIS Felix, BISPO VIEIRA Ricardo, BLANC Benjamin,
BORDESSOULES Arthur, BOUDJEMAI Yassine, BRICAGE Marie, ETSCHMANN Marc, GAYE
Ndeye Aram, GONCALVES Thomas, GOUGEAUD Sebastien, HAINE Christopher, OLIVEIRA
Pablo, PLAZA ONATE Florian, POPOV Mihail

--------------------------------------------------------------------------------

Jonesforth-ARM is a Forth interpreter developed for ARM.

Another project porting Jonesforth on ARM is currently going by phf at
https://github.com/phf/forth

The algorithm for our unsigned DIVMOD instruction is extracted from 'ARM
Software Development Toolkit User Guide v2.50' published by ARM in 1997-1998

--------------------------------------------------------------------------------

Compared to the original interpreter:
	- We removed the possibility for the interpreter to recognize assembler
	  instructions because it is X86 specific
	- We added a signed DIVMOD instruction (S/MOD)

--------------------------------------------------------------------------------

Installation instruction:
	$ make

Running instruction:
	$ ./jonesforth