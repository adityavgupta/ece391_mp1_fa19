
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
    pushl %ebp # stack setup
		movl  %esp, %ebp

		pushl %ebx # callee save registers
		pushl %esi
		pushl %edi

		pushl %eax # caller save register
		pushl %edx
		pushl %ecx

		cmpl  $0, current_board # check for a null pointer
		je    end_tasklet

		movl  $1, %ebx # row  counter
		movl  $0, %edx # clear register to keep track of alive cells in next_board


 row_loop:
    movl  $1, %edi
 column_loop:
    imull $SCR_WIDTH, %ebx, %esi
		addl %edi, %esi
		movl %esi, %ecx
    addl current_board, %esi

    pushl %edx # caller save
    pushl %ecx

		# neighbor count and tick result help determine if the cell is alive or dead in next_board
		# int neighbor count (unsigned char* cell)
		  # neighbour count parameters: pointer to the board

		# int tick result (unsigned char cur, int neighbors);
		  # tick result parameters: (1) result from neighbor_count (2) value in the cell in current board

		pushl %esi
		call  neighbor_count
		popl  %esi

    pushl %eax
		pushl (%esi)
		call  tick_result
		addl  $8, %esp
		popl  %ecx
		popl  %edx

		addl next_board, %ecx
		movb %al, (%ecx)

		cmpl $0, %eax
		je   dead_cell
    inc  %edx

  dead_cell:
	  inc  %edi
		cmpl $SCR_WIDTH-2, %edi
		jle  column_loop

		inc  %ebx
		cmpl $SCR_HEIGHT-2, %ebx
		jle  row_loop

		imull $10, %edx
    movl  %edx, infection

   # part 2 of the tasklet: swapping the two baord pointers
   # swap by using a temp register

	  movl next_board, %ebx
	  movl %ebx, %esi
	  movl current_board, %ebx
	  movl %ebx, next_board
	  movl %esi, current_board


	 # part 3 of tasklet: subtract new infection value from population
	  movl infection, %ebx
	  movl population, %esi
	  subl  %ebx, %esi
	  cmpl  $0, %esi
	  jge   above_zero
	  movl  $0, population

    jmp   to_draw_screen

  above_zero:
    movl  %esi, population

  to_draw_screen:
	 call   draw_screen

   # notify user before leaving
	 call  mp1_notify_user

end_tasklet:
		popl  %ecx # stack tear down
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

    # compare the argument values and jump to the respective ioctl
		cmp  $0, %eax
		je   mp1_ioctl_startgame

		cmp  $1, %eax
		je	 mp1_ioctl_endgame

		cmp  $2, %eax
		je   mp1_ioctl_keystroke

		cmp  $3, %eax
		je	 mp1_ioctl_getstatus

		cmp  $4, %eax
		je   mp1_ioctl_vaccinate

		movl $-1, %eax # return value is -1
		ret


# ----------------- Functions private to this file -------------------

/* *draw_screen uses the information in the current board about
   a cell, assigns the appropriate characters to the cell and then
   draws it.

	 * current board stores 0 and 1 for dead and alive cells resp
*/

draw_screen:
	# For simplicity, your implementation may assume a SCR_WIDTH of 80.
	  pushl %ebp  # stack setup
		movl %esp, %ebp

		pushl %ebx
		pushl %esi
		pushl %edi

		pushl %edx # push edx since it is used to get the offset later

    movl $0, %esi # counter

	drawing_loop:
	  imull $2, %esi, %eax
    movl current_board, %edi

    movl $0, %edx
		addl %edi, %edx

		addl %esi, %edx # offset from the current_board
		movb (%edx), %bl # get the info about cell's state (1 byte)

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
		jb  drawing_loop

		popl  %edi  # callee pop registers
		popl  %esi
		popl  %ebx

    leave
		ret

 /* mp1_ioctl_startgame
  * This function is called when the game is about to start in order to initialize the variables used by the driver.
  * seed_generator takes the parameter to generate an argument for seed
	* This function also allocates memory for current_board and next_board
	* sets the initial values for aggression = 80, population = 8000000
  */
mp1_ioctl_startgame:
		pushl %ebp # stack setup
		movl  %esp, %ebp

		pushl %ebx
		pushl %esi
		pushl %edi

		pushl %eax
		pushl %edx
		pushl %ecx

		pushl 8(%ebp) # argument push
		call  seed_generator
		add   $4, %esp # remove parameter

		pushl $SCR_SIZE # allocate memory
		call  mp1_malloc
		add   $4, %esp

		cmpl  $0, %eax # null pointer check
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
    pushl current_board # free current_board
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
		ja    board_1_counter # exit loop when counter = 0 i.e. loop SCR_SIZE times

		movl $SCR_SIZE, %ebx
		movl next_board, %eax

	board_2_counter:
	  movb  $0, (%eax)
	  inc   %eax
	  dec   %ebx
	  cmpl  $0, %ebx
		ja    board_2_counter

		pushl current_board # call init_virus on current_board
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
		popl  %ecx # stack tear down
		popl  %edx
		addl  $4, %esp

		popl  %edi
		popl  %esi
		popl  %ebx

    leave
		ret

/* mp1_ioctl_endgame
*  This function frees the memory allocated to the boards.
*  Sets the pointers to the boards back to zero
*/
mp1_ioctl_endgame:
    pushl %ebp # stack setup
    movl %esp, %ebp

    pushl %ebx # callee save registers
    pushl %esi
    pushl %edi

    pushl %edx # caller save
    pushl %ecx

		pushl current_board
		call  mp1_free
		addl  $4, %esp

		pushl next_board
		call  mp1_free
		addl  $4, %esp

		popl  %ecx
		popl  %edx
		popl  %edi
		popl  %esi
		popl  %ebx

		movl  $0, current_board
		movl  $0, next_board
		movl  $0, %eax
		leave
		ret

/* mp1_ioctl_keystroke
* the direction is dpecified in the struct of keystroke
* left/right erases the current selector and draws to the new one
  according to the button pressed
* the up and down change the letter value
* pressing the up and down button changes the guess value according
  to the hints in the
*/
mp1_ioctl_keystroke:
    pushl %ebp # stack setup
		movl  %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

    cmpl $0, 8(%ebp)  # check if the prameter is valid
    je   kys_fail

    subl $KA_STACK, %esp # allocate space for KA_STACK

		movl %esp, %ebx # save a copy of stack top pointer into ebx

		pushl %ecx # caller save
		pushl %edx

		pushl $KA_SIZE # push arguments for struct setup in kernel
		pushl 8(%ebp)
		pushl %ebx
		call mp1_copy_from_user
		addl $12, %esp

		popl  %edx # pop caller registers
		popl  %ecx

    cmpl  $0, %eax # if null pointer returned then keystrokes fails
		jne   kys_fail

		movw  (%ebx), %ax
		test  $1, %ax # and it with 1 to determine weather it is a left/right or up/down
		je    left_or_right

		cmp   $1, %ax # if 1 then it is up direction
		jne   up

  # down implementation
  		movl  $0, %edx
		movw  2(%ebx), %dx
		movb  4(%ebx, %edx), %cl

		recheck_down:
		cmp   $0, %cl
		je    down_zero

		add  $-1, %cl
		jmp   check_hint_d

		down_zero:
		mov   $3, %cl

		check_hint_d:
		mov   $0, %eax
		mov   9(%edx, %ebx), %al
		mov   %eax, %esi
		shrl  %cl, %esi
		test  $1, %esi
		je 		recheck_down

		mov   %cl, 4(%ebx, %edx)

		jmp   draw_up_down

# up implementation
  	up:
  		movl  $0, %edx
		movw  2(%ebx), %dx
		movb  4(%ebx, %edx), %cl

		recheck_up:
		cmp		$3, %cl
		je    up_three

		add   $1, %cl
		jmp   check_hint_u

		up_three:
		mov   $0, %cl

		check_hint_u:
		mov   $0, %eax
		mov   9(%edx, %ebx), %al
		mov   %eax, %esi
		shrl  %cl, %esi
		test  $1, %esi
		je 		recheck_up

	  	mov   %cl, 4(%ebx, %edx)

	draw_up_down:
		mov   %edx, %eax
		imull $10,  %eax
		addl  $18, %eax
		addl  $1760, %eax
		imull $2, %eax

		mov %ecx, %esi
		add $base_array, %esi
		movb (%esi), %cl

		pushl %edx
		call mp1_poke
		popl %edx

		jmp kys_success


 # implementation for left and right
	left_or_right:
	  	movl $select_blank, %esi  # pointer to select_blank
		movl $0, %edi             # setup counter

  	selector_blank_loop:
    	movl $0, %eax
		movw SELECTOR(%esp), %ax
		imull $10, %eax  # get the offset according to (14+10S, 22)
		addl  $14, %eax
		addl  $1760, %eax # 22*80 = 1760. this is the positions for the selector to be written
		addl  %edi, %eax
		imull $2, %eax, %eax
		movb (%esi, %edi), %cl
		pushl %edx
		call mp1_poke
		popl %edx

		inc %edi
		cmpl $3, %edi # size of selector is 3 hence the comparison
		jl   selector_blank_loop

		cmpw $0, (%esp)
		je   left

		movw SELECTOR(%esp), %ax
		add  $1, %ax
		cmp  $4, %ax
		jg   right_loop_around
		movw %ax, SELECTOR(%esp)
		jmp draw_left_right

		right_loop_around:
		movw $0, SELECTOR(%esp)
		jmp  draw_left_right


	 left:
     	movw SELECTOR(%esp), %ax
		add  $-1, %ax
		cmp  $0, %ax
		jl   left_loop_around

	    movw  %ax, SELECTOR(%esp)
        jmp  draw_left_right

   left_loop_around:
		movw  $4, SELECTOR(%esp)
		jmp   draw_left_right

	 draw_left_right:
		movl $select_image, %esi
	  	movl $0, %edi             # setup counter

	 selector_fill_loop:   # the loop to draw the selector
		movl $0, %eax
	  	movw SELECTOR(%esp), %ax
	  	imull $10, %eax  # as explained above
	  	addl  $14, %eax
	  addl  $1760, %eax
	  addl  %edi, %eax
	  imull $2, %eax, %eax
	  movb (%esi, %edi), %cl
	  pushl %edx
	  call mp1_poke
	  popl %edx

	  inc %edi
	  cmpl $3, %edi
	  jl   selector_fill_loop

		jmp kys_success


  kys_fail:
	  movl  $-1, %eax
    jmp kys_pop
	kys_success:
	 pushl %ecx
	 pushl %edx

	 pushl $KA_SIZE
	 pushl %ebx
	 pushl 8(%ebp)

	 call mp1_copy_to_user

	 addl $12,%esp

	 popl %edx
	 popl %ecx

	 addl $KA_STACK,%esp
	 movl $0, %eax
	kys_pop:
		popl  %edi # stack pop
		popl  %esi
		popl  %ebx
		leave
		ret
/* mp1_ioctl_getstatus
* This function allows the user code to retrieve the current population and virus infection count from
  the kernel variables (population and infection)
* Argument provides a pointer to a structure in user space into which the function
  must copy these values.
*/
mp1_ioctl_getstatus:
    pushl %ebp
		movl  %esp, %ebp

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

/* mp1_ioctl_vaccinate
* This function handles the work necessary for vaccination
* The parameter packed args is a 32-bit integer containing two unsigned
  16-bit integers packed into its low and high words
* The low 16 bits contain the percentage chance that a live cell in the
  current board should be killed (set to 0)
* generate function generates a 32-bit unsigned random number, whihch is used to calculate the remainder of that
number when divided by 100, then compare with the given percentage to determine whether or not to kill that cell
* high 16 bits are added to aggression
*/

mp1_ioctl_vaccinate:
    pushl %ebp # stack setup
    movl %esp, %ebp

    pushl %ebx
    pushl %esi
    pushl %edi

		pushl %ecx
		pushl %edx

		movl current_board, %edi
		movw 10(%ebp), %bx
		addw %bx, aggression
		movw 8(%ebp), %cx

		movl $0, %esi

	vac_loop:

		call generate

		movl $0, %edx
		movl $100, %ebx

		div %ebx

		cmpw 8(%ebp), %dx
		jle  cell_died

		inc %esi
		cmp $SCR_SIZE, %esi
		jl  vac_loop

		jmp vac_ends

  cell_died:
	  movb $0, (%esi, %edi)
		inc %esi
		cmp $SCR_SIZE, %esi
		jl  vac_loop


	vac_ends:
    movl $0, %eax # this function always returns 0

		popl %edx # stack tear down
    popl %ecx
 	  popl  %edi
    popl  %esi
 		popl  %ebx

 		leave
		ret
