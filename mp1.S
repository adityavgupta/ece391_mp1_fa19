
# mp1.S - life-or-death version
# Good luck, and have fun!

.data

    # Constants for accessing the fields of a struct keystroke_args
    # struct keystroke_args is defined in rtc.h and mp1.h

	KA_SIZE	  = 14   # 14 bytes when copying
	KA_STACK  = 16   # use 16 bytes on stack for alignment
	DIRECTION = 0
	SELECTOR  = 2
	GUESS     = 4
	HINT      = 9

    # Constants for accessing the fields of a struct game_status
    # struct game_status is defined in rtc.h and mp1.h

	GS_SIZE   = 8	# 8 bytes
	POP 	  = 0
	INF	  = 4

    # Constants for screen size

  SCR_WIDTH  = 80
	SCR_HEIGHT = 20
	SCR_SIZE   = ((SCR_WIDTH) * (SCR_HEIGHT))

    # ASCII cell images

  CELL_LIVE = 0x78
	CELL_DEAD = 0x20


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl rand_seed, aggression

			.align 8
rand_seed:		.quad 0x0	# Pseudo-random number seed
aggression:		.long 0x0	# Aggression level of virus


# Data private to this file

current_board:		.long 0x0	# Address of current board
next_board:		.long 0x0	# Address of next board
population:		.long 0x0	# Remaining human population
infection:		.long 0x0	# Count of live virus cells
select_image:		.string "==>"	# Picture of the selector
select_blank:		.string "   "	# Picture to overwrite selector
base_array:             .string "ACGT"  # Array of characters for bases


.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long ignore);
# Performs three tasks:
#	(1) updates the life game board and calculates infection count
#	(2) swaps the two boards
#	(3) applies population reduction based on infection count
#	(4) redraws the screen
#	(5) notifies the user code by calling mp1_notify_user
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
    pushl %ebp
		movl  %esp, %ebp

		pushl %ebx # callee save registers
		pushl %esi
		pushl %edi

		pushl %eax # caller save register
		pushl %edx
		pushl %ecx

		cmpl  $0, current_board
		je    end_tasklet

		movl  $1, %ebx # row  counter
		xorl  %edx, %edx # clear register to keep track of alive cells in next_board
 row_loop:
    movl  $1, %edi # set column counter to 1
 column_loop:
    imull $SCR_WIDTH, %ebx, %esi # current_row*80 -> esi
		addl %edi, %esi # current_row*80 + current_column -> esi
		movl %esi, %ecx
    addl current_board, %esi

    pushl %ecx
		pushl %esi
		call  neighbor_count
		popl  %esi


    pushl %eax
		pushl (%esi)
		call  tick_result
		addl  $8, %esp
		popl  %ecx

		addl next_board, %ecx
		movl %eax, (%ecx)


		cmpl $0, %eax
		je   dead_cell
    inc  %edx

  dead_cell:
	  inc  %edi
		cmpl $78, %edi
		jbe  column_loop

		inc  %ebx
		cmpl $18, %ebx
		jbe  row_loop

		imull $10, %edx
    movl  %edi, infection

   # part 2 of the tasklet: swapping the two baord pointers

	 movl next_board, %ebx # next_board->ebx
	 movl %ebx, %esi  # ebx->esi
	 movl current_board, %ebx  # current_board->ebx
	 movl %ebx, next_board  # ebx->next_board i.e. next board gets updated to current_board
	 movl %esi, current_board # esi->current_board i.e. current board gets updated to next_board


	 # part 3 of tasklet: subtract new infection value from population
	 movl infection, %ebx
	 movl population, %esi
	 subl  %ebx, %esi
	 cmpl  $0, %esi
	 jae   above_zero
	 movl  $0, population

   jmp   to_draw_screen

 above_zero:
   movl  %esi, population

 to_draw_screen:
	 call   draw_screen

	 call  mp1_notify_user
end_tasklet:
		popl  %ecx
		popl  %edx
		popl  %eax

		popl  %edi
		popl  %esi
		popl  %ebx

		leave
		ret


# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		movl 8(%esp), %eax # move argument into eax

		cmp  $0, %eax # eax- 0
		je   mp1_ioctl_startgame

		cmp  $1, %eax # eax-1
		je	 mp1_ioctl_endgame

		cmp  $2, %eax # eax-2
		je   mp1_ioctl_keystroke

		cmp  $3, %eax # eax-3
		je	 mp1_ioctl_getstatus

		cmp  $4, %eax # eax - 4
		je   mp1_ioctl_vaccinate

		movl $-1, %eax # any other value put -1 into eax
		ret


# ----------------- Functions private to this file -------------------


draw_screen:
	# For simplicity, your implementation may assume a SCR_WIDTH of 80.
	  pushl %ebp
		movl %esp, %ebp

		pushl %ebx  # callee save registers
		pushl %esi
		pushl %edi

    movl $0, %esi # counter

	drawing_loop:
	  imull $2, %esi, %eax
    movl current_board, %edi # edi points to start of game board
		movb (%edi, %esi), %bl
		cmpb $0, %bl
		je   cel_ded
		movb $CELL_LIVE, %cl
		jmp  poke_it
	 cel_ded:
		movb  $CELL_DEAD, %cl
	 poke_it:
		push %edx
		call mp1_poke
		pop %edx

		inc %esi
		cmp $SCR_SIZE, %esi
		jl  drawing_loop

		popl  %edi  # callee pop registers
		popl  %esi
		popl  %ebx

    leave
		ret

mp1_ioctl_startgame:
		pushl %ebp # push old base pointer
		movl %esp, %ebp

		pushl %ebx # callee save registers
		pushl %esi
		pushl %edi

		pushl %eax # caller save register
		pushl %edx
		pushl %ecx

		pushl 8(%ebp) # argument push
		call  seed_generator
		add   $4, %esp # remove parameter

		pushl $SCR_SIZE # allocate memory
		call  mp1_malloc
		add   $4, %esp

		cmpl  $0, %eax # compare the value of pointer returned from malloc with null (eax - 0)
	  je    alloc_fail
		movl  %eax, current_board # move the pointer to the current board(eax) into the label 'current board'

		pushl $SCR_SIZE # allocate memory for board #2
		call  mp1_malloc
		add   $4, %esp

		cmpl  $0, %eax
		je    board_2_fail
		movl  %eax, next_board # move the pointer to the next board(eax) into the label 'next_board'
		jmp   alloc_success

board_2_fail:
    pushl $current_board # free current_board
		call  mp1_free
		add   $4, %esp

		movl  $0, current_board

		jmp   alloc_fail

alloc_success:

    movl  $SCR_SIZE, %ebx # set up counter to fill the board with 0 bytes
		movl  current_board, %eax
	board_1_counter:
		movb  $0, (%eax)
		inc   %eax   # increment the position in the board array
		dec   %ebx   # decrement counter
		cmpl  $0, %ebx
		ja    board_1_counter # exit loop when counter = 0 i.e. loop 1600 (SCR_SIZE) times

		movl $SCR_SIZE, %ebx
		movl next_board, %eax
	board_2_counter:
	  movb  $0, (%eax)
	  inc   %eax   # increment the position in the board array
	  dec   %ebx   # decrement counter
	  cmpl  $0, %ebx
		ja    board_2_counter

		pushl $current_board # call init_virus on current_board
		call  init_virus
		add   $4, %esp

		movl %eax, infection # move the return value from init_virus
    movl $80, aggression
		movl $8000000, population

		movl $0, %eax # set return value to 0 is successful
		jmp  final_pop

alloc_fail:
    movl $-1, %eax # set return value to -1 if fail

final_pop:
		popl  %ecx # caller pop
		popl  %edx
		addl  $4, %esp

		# recall callee saved register
		popl  %edi
		popl  %esi
		popl  %ebx

    leave
		ret

mp1_ioctl_endgame:
    pushl %ebp # push old base pointer
    movl %esp, %ebp

    pushl %ebx # callee save registers
    pushl %esi
    pushl %edi

    pushl %edx # caller save
    pushl %ecx

		pushl $current_board
		call  mp1_free
		addl  $4, %esp
		movl  $0, current_board

		pushl $next_board
		call  mp1_free
		addl  $4, %esp
		movl  $0, next_board

		popl  %ecx
		popl  %edx
		popl  %edi
		popl  %esi
		popl  %ebx

		movl $0, %eax
		leave
		ret

mp1_ioctl_keystroke:

		ret

mp1_ioctl_getstatus:
    pushl %ebp
		movl %esp, %ebp

    pushl %ebx # callee save registers
    pushl %esi
    pushl %edi

    cmp $0, 8(%ebp)
		je  fail_gs

		push infection
		push population
		mov  %esp, %ebx

		push %ecx
		push %edx
		push $GS_SIZE
		push %ebx
		push 8(%ebp)
		call mp1_copy_to_user
		add $12, %esp
		pop %edx
		pop %ecx

		add $GS_SIZE, %esp

		cmp $0, %eax
		je  success_gs

  fail_gs:
	  mov $-1, %eax
		jmp pops

	success_gs:
	  mov $0, %eax

	pops:
		popl  %edi # callee pop
    popl  %esi
		popl  %ebx

		leave
		ret

mp1_ioctl_vaccinate:
		ret
