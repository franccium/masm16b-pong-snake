; for phase errors - try to only use 16-bit registers
.386
instr SEGMENT use16
ASSUME cs:instr
update_snake PROC
	push ax
	push bx
	push es
	push cx
	mov eax, 0
	mov ax, 0A000H
	mov es, ax

	call update_pong

	cmp dh, cs:collision_flag
	je end_snake_movement
	mov dh, cs:is_snake_game_paused
	cmp dh, 1
	je end_snake_movement

	call update_snake_pos

	; shift directions by frame
	movzx cx, cs:snake_size
	sub ecx, 1
	movzx si, cs:snake_size
	lea esi, [esi * 2 - 2] ; iterate n..0
	shift_directions:
		sub esi, 2
		mov bx, cs:dir_previous[esi]
		mov cs:dir_previous[esi + 2], bx ; the previous segment gets the direction of the next segment
		loop shift_directions

	; check whether head collides with the body
	movzx cx, cs:snake_size
	sub cx, 1
	mov si, 2 ; iterate 1..n
	mov bx, cs:pos_previous ; head pos
	check_collision:
		mov ax, cs:pos_previous[si]
		cmp ax, bx
		je handle_snake_collision
		add si, 2
		loop check_collision

	; check for collisions with board bounds
	; left bound --> pos % 320 == 0
	mov ax, cs:pos_previous ; head pos
	mov cx, 320
	mov edx, 0
	div cx
	test edx, edx
	jz handle_snake_collision
	; right bound --> pos + % 319 == 0
	mov ax, cs:pos_previous ; head pos
	mov cx, 319
	mov edx, 0
	div cx
	test edx, edx
	jz handle_snake_collision
	; top bound --> pos < 320
	mov ax, cs:pos_previous ; head pos
	cmp ax, 320
	jb handle_snake_collision
	; bottom bound --> pos >= 320 * 199
	mov ax, cs:pos_previous ; head pos
	cmp ax, 320 * 199
	jae handle_snake_collision

	next:
	
	; check collisions with apples
	mov esi, 0
	mov si, 0
	mov bx, cs:pos_previous ; head pos
	check_apple_collision:
		mov ax, cs:apple_positions[si]
		cmp ax, bx
		je handle_apple_collision

		add si, 2
		cmp si, apple_count * 2
		jb check_apple_collision
	jmp end_snake_movement

	handle_apple_collision:
		call update_apple_collision
		jmp end_snake_movement

	handle_snake_collision:
		mov dh, cs:collision_flag
		jmp end_snake_movement
	
	end_snake_movement:
	pop cx
	pop es
	pop bx
	pop ax
	jmp dword PTR cs:clock_handler_address ; back to original proc
	
	; variables
	pos_max dw 320*200 - 1
	snake_initial_pos dd 2050
	apple_initial_pos dw 2060
	max_snake_size equ 1000
	apple_count equ 250
	cluster_apple_count equ 25 ; part of total apples, just for testing
	pos_previous dw max_snake_size dup (?)
	apple_positions dw apple_count dup (?)
	snake_size dw 90
	snake_color db 05H
	apple_color db 2AH
	board_color db 0B1H
	last_random_number dw 5823H ; initially the seed
	last_scaling_random_factor dw 392H
	last_direction dw 1
	collision_flag db 144
	dir_previous dw max_snake_size dup (1)
	ball_pos_x dw 50
	ball_pos_y dw 80
	ball_speed_x dw -3
	ball_speed_y dw 1
	ball_speed db 3
	ball_dir_x db 1
	ball_dir_y db -1
	ball_color db 0FH
	last_ball_complete_position dw 0
	racket_size equ 50
	racket1_y_pos db 100
	racket2_y_pos db 70
	racket1_y_dir db -1
	racket2_y_dir db 1
	racket_speed equ 2
	racket_x_offset equ 10

	; bound hit prediction for enemy ai
	hit_y_bound_in_turns dw 0
	x_at_next_y_bound_hit dw 0
	y_at_next_y_bound_hit dw 0
	hit_x_bound_in_turns dw 0
	x_at_next_x_bound_hit dw 0
	y_at_next_x_bound_hit dw 0

	is_pong_game_paused db 0
	is_snake_game_paused db 0

	text_color db 0FH
	game_title_text_color db 0DH 
	txt_ball_speed_x db 'ball speed X:', 0
	txt_ball_speed_y db 'ball speed Y:', 0
	txt_ball_pos_x db 'ball pos X:', 0
	txt_ball_pos_y db 'ball pos Y:', 0
	pad db 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 0

	clock_handler_address dd ?
update_snake ENDP

update_snake_pos PROC
	movzx cx, cs:snake_size
	mov esi, 0
	move_snake:
		mov bp, cs:pos_previous[esi]

		mov bl, cs:board_color
		mov es:[ebp], bl
		mov ax, cs:dir_previous[esi]
		add bp, ax
		cmp bp, cs:pos_max
		jne write_pos
		mov bp, 0

		write_pos:
		mov cs:pos_previous[esi], bp

		mov bl, cs:snake_color
		mov es:[ebp], bl
		add esi, 2
		loop move_snake
	ret
update_snake_pos ENDP

update_apple_collision PROC
	push esi
	push ecx
	push ebp
	; delete the eaten apple, spawn a new one
	; apple pos in eax
	; apple index in esi
	; just replace the apple from the current index with the new one
	call generate_new_random_number
	; ax has a random position for a new apple to spawn at

	mov cs:last_random_number, ax
	mov cs:apple_positions[si * 2], ax
	mov bp, ax
	mov bl, cs:apple_color
	mov es:[bp], bl

	; grow snake
	mov si, cs:snake_size
	add cs:snake_size, 1 
	lea esi, [esi * 2]
	mov bx, cs:pos_previous[esi - 2]
	mov cx, cs:dir_previous[esi - 2]
	sub bx, cx
	mov cs:pos_previous[esi], bx
	mov cs:dir_previous[esi], cx ; copy the last direction

	pop ebp
	pop ecx
	pop esi
	ret
update_apple_collision ENDP

update_pong PROC
	push ebp
	push ebx
	push edi
	push esi
	push edx


	mov dh, cs:is_pong_game_paused
	cmp dh, 1
	je end_pong_update
		;mov eax, 0
	;mov ax, cs:ball_pos_y
	;mov bx, 320
	;imul bx
	;add ax, cs:ball_pos_x
	;mov bp, ax
	;mov bl, cs:ball_color
	;mov es:[bp], bl

	mov ax, 0
	;mov bh, cs:ball_dir_x
	;mov al, cs:ball_speed
	;imul bh
	mov ax, cs:ball_speed_x
	add ax, cs:ball_pos_x
	cmp ax, 1
	jle collide_left_bound
	cmp ax, 319
	jge collide_left_bound
	;mov bh, cs:ball_dir_y
	;mov al, cs:ball_speed
	;imul bh
	calculate_y_pos:
	mov ax, cs:ball_speed_y
	add ax, cs:ball_pos_y
	cmp ax, 1
	jle collide_upper_bound
	cmp ax, 199
	jge collide_upper_bound

	jmp draw_ball

	collide_left_bound:
		neg cs:ball_speed_x
		jmp calculate_y_pos

	collide_upper_bound:
		neg cs:ball_speed_y
		jmp draw_ball

	; if hit upper/lower bound, negate y speed
	; cmp y to 0
	; if hit left/right bound, negate x speed

	draw_ball:
		; clear old ball pos
		mov bp, cs:last_ball_complete_position
		mov bl, cs:board_color
		mov es:[bp], bl

		mov ax, cs:ball_speed_x
		add ax, cs:ball_pos_x
		mov cs:ball_pos_x, ax
		mov cx, ax ; newX in cx
		mov ax, cs:ball_speed_y
		add ax, cs:ball_pos_y
		mov cs:ball_pos_y, ax
		mov bx, 320
		imul bx
		add ax, cx
		mov bp, ax
		mov bl, cs:ball_color
		mov es:[bp], bl
		mov cs:last_ball_complete_position, bp

	update_enemy_ai:
		cmp cs:y_at_next_x_bound_hit, 0
		jl skip_update_ai
		cmp cs:y_at_next_x_bound_hit, 210
		jg skip_update_ai
		mov bx, cs:y_at_next_x_bound_hit
		movzx ax, cs:racket2_y_pos
		sub ax, bx
		cmp ax, 0
		je dont_move
		jg move_up
		mov cs:racket2_y_dir, 1
		jmp next_update_ai
		dont_move:
		mov cs:racket2_y_dir, 0
		jmp next_update_ai
		move_up:
		mov cs:racket2_y_dir, -1
		next_update_ai:
		; can make enemy move faster when he wont make it or sth

	skip_update_ai:

	move_rackets:
		mov al, racket_speed
		mov bl, cs:racket1_y_dir
		imul bl
		add al, cs:racket1_y_pos
		cmp al, racket_size / 2
		jg can_move1
		cmp al, 200 - racket_size / 2
		jl can_move1
		; collided with board bounds
		neg cs:racket1_y_dir

		can_move1:
		mov cs:racket1_y_pos, al

		move_racket2:
		mov al, racket_speed
		mov bl, cs:racket2_y_dir
		imul bl
		add al, cs:racket2_y_pos
		cmp al, racket_size / 2
		jg can_move2
		; check if within the y = 210 bound
		cmp al, 200 - racket_size / 2
		jl can_move2
		; collided with board bounds
		cmp cs:racket2_y_dir, 0
		movzx ax, al
		imul cs:racket2_y_dir
		cmp dx, 0
		jl is_moving_away_from_the_bound
		; moving in the same way as the bound, stop the racket
		mov cs:racket2_y_dir, 0
		is_moving_away_from_the_bound:
		jmp draw_rackets

		can_move2:
		mov cs:racket2_y_pos, al

	draw_rackets:
		; draw racket 1
		movzx ax, cs:racket1_y_pos
		sub ax, racket_size / 2
		mov bx, 320
		mul bx
		add ax, racket_x_offset
		mov bp, ax
		
		mov bl, cs:racket1_y_dir
		cmp bl, -1
		je clear_down
		; clear up
		mov bl, cs:board_color
		mov es:[bp - 320], bl
		mov es:[bp - 320*2], bl
		jmp skip_clear
		clear_down:
		add bp, racket_size * 320
		mov bl, cs:board_color
		mov es:[bp], bl
		mov es:[bp + 320], bl
		mov bp, ax

		skip_clear:
		mov cx, racket_size
		draw_racket_loop:
			mov es:[bp], byte ptr 0FH
			add bp, 320
			loop draw_racket_loop

		; draw racket 2
		movzx ax, cs:racket2_y_pos
		sub ax, racket_size / 2
		mov bx, 320
		mul bx
		add ax, 319
		sub ax, racket_x_offset
		mov bp, ax

		mov bl, cs:racket2_y_dir
		cmp bl, -1
		je clear_down2
		; clear up
		mov bl, cs:board_color
		mov es:[bp - 320], bl
		mov es:[bp - 320*2], bl
		jmp skip_clear2
		clear_down2:
		add bp, racket_size * 320
		mov bl, cs:board_color
		mov es:[bp], bl
		mov es:[bp + 320], bl
		mov bp, ax

		skip_clear2:
		mov cx, racket_size
		draw_racket_loop2:
			mov es:[bp], byte ptr 0FH
			add bp, 320
			loop draw_racket_loop2

	; ball racket collision
	mov ax, cs:ball_pos_x
	add ax, cs:ball_speed_x ; if the ball moved past the racket with x speed, add instead of sub cause speed is negative
	cmp ax, racket_x_offset
	jle racket1_collision_on_x_pos
	mov bx, 320
	sub bx, racket_x_offset
	cmp ax, bx
	jl no_collision_on_x_pos
	; racket2_collision_on_x_pos
	; check whether y pos collided with the racket: if its distance to r.ypos is < r.size/2
	mov ax, cs:ball_pos_y
	movzx bx, cs:racket2_y_pos
	sub ax, bx
	test ax, ax
	jnz no_abs
	neg ax
	no_abs:
	cmp ax, racket_size / 2
	jg no_collision_on_x_pos
	; collided with a racket
	neg cs:ball_speed_x ; flip x speed
	jmp no_collision_on_x_pos

	; racket2 collision on x pos
	mov ax, cs:ball_pos_y
	movzx bx, cs:racket2_y_pos
	sub ax, bx
	mov cx, racket_size / 2 / 3
	mov dx, 0
	cmp ax, 0
	jg aasdsa
	mov dx, 0FFFFH
	aasdsa:
	idiv cx
	add ax, 1
	mov cs:ball_speed_y, ax
	jmp no_collision_on_x_pos

	racket1_collision_on_x_pos:
	mov ax, cs:ball_pos_y
	movzx bx, cs:racket1_y_pos
	sub ax, bx
	test ax, ax
	jnz no_abs2
	neg ax
	no_abs2:
	cmp ax, racket_size / 2
	jg no_collision_on_x_pos
	; collided with a racket
	neg cs:ball_speed_x ; flip x speed

	; y speed = r.center - ball.yPos
	; racket_size/2 = 25
	; for each 3 pixels of distance yspeed + 1 starting with 1
	mov ax, cs:ball_pos_y
	movzx bx, cs:racket1_y_pos
	sub ax, bx
	mov cx, racket_size / 2 / 3
	mov dx, 0
	cmp ax, 0
	jg aasdsa2
	mov dx, 0FFFFH
	aasdsa2:
	idiv cx
	add ax, 1
	mov cs:ball_speed_y, ax


	; bound hit prediction
	cmp cs:ball_speed_y, 0
	jge going_down
	; going up, to y = 0
	mov ax, cs:ball_pos_y
	mov bx, cs:ball_speed_y
	neg bx
	mov dx, 0
	div bx
	mov cs:hit_y_bound_in_turns, ax
	jmp calculate_x

	going_down:
	mov bx, cs:ball_pos_y
	mov ax, 210
	sub ax, bx
	mov bx, cs:ball_speed_y
	cmp bx, 0
	jg dontnegatespeed
	cmp bx, 0
	je skip_predicition_cause_y_dir_0
	neg bx
	dontnegatespeed:
	mov dx, 0
	div bx
	; bx = turns needed to hit the lower bound
	mov cs:hit_y_bound_in_turns, ax

	; x at next bound hit = x + turns * xSpeed
	calculate_x:
	mov bx, cs:ball_speed_x
	imul bx
	add ax, cs:ball_pos_x
	; if x > 319 its a direct right bound hit, so need to change logic, with y pos at hit being the max it can be
	cmp ax, 319
	jle hits_lower_bound

	; direct right bound hit
	; turns = 320 - x / xSpeed
	mov ax, 320
	mov bx, cs:ball_pos_x
	sub ax, bx
	mov bx, cs:ball_speed_x
	cmp bx, 0
	jg dontnegatexspeed3
	neg bx
	cmp bx, 0
	dontnegatexspeed3:
	div bx
	mov cs:hit_x_bound_in_turns, ax
	mov bx, cs:ball_speed_y
	imul bx
	mov bx, cs:ball_pos_y
	add bx, cs:ball_pos_y
	;cmp bx, 0
	;jg dont_check_for_second_y_bound_bounce
	mov cs:y_at_next_x_bound_hit, bx
	jmp gonextwow


	hits_lower_bound:
	mov cs:x_at_next_y_bound_hit, ax

	y_at_next_bound_hit:
	; y at next bound hit = y + turns * ySpeed
	mov ax, cs:hit_y_bound_in_turns
	mov bx, cs:ball_speed_y
	imul bx
	add ax, cs:ball_pos_y
	mov cs:y_at_next_y_bound_hit, ax

	right_bound_after_lower_bound:
	; heading for x = 320
	mov ax, 320
	mov bx, cs:x_at_next_y_bound_hit
	sub ax, bx
	mov bx, cs:ball_speed_x
	cmp bx, 0
	jg dontnegatexspeed
	neg bx
	cmp bx, 0
	je skip_predicition_cause_x_dir_0
	dontnegatexspeed:
	mov dx, 0
	div bx
	mov cs:hit_x_bound_in_turns, ax
	; y at next x bound hit 
	mov bx, cs:ball_speed_y
	imul bx
	mov bx, 210
	cmp cs:ball_speed_y, 0
	jg subfrom210
	mov bx, 0
	subfrom210:
	sub bx, ax
	cmp bx, 0
	jg dont_check_for_second_y_bound_bounce
	; TODO

	dont_check_for_second_y_bound_bounce:
	mov cs:y_at_next_x_bound_hit, bx
	jmp gonextwow

	skip_predicition_cause_x_dir_0:
	; how 
	mov ax, cs:ball_pos_x
	mov cs:x_at_next_x_bound_hit, ax
	mov cs:x_at_next_y_bound_hit, ax
	jmp gonextwow

	skip_predicition_cause_y_dir_0:
	mov ax, cs:ball_pos_y
	mov cs:y_at_next_x_bound_hit, ax
	mov cs:y_at_next_y_bound_hit, ax
	jmp gonextwow

	gonextwow:

	no_collision_on_x_pos:

	end_pong_update:
	pop edx
	pop esi
	pop edi
	pop ebx
	pop ebp
	ret
update_pong ENDP

color_background PROC
	push ebp
	push ebx

	mov ebp, 0
	mov bl, cs:board_color
	color_board:
		mov es:[bp], bl
		inc bp
		cmp bp, 320*200
		jb color_board

	pop ebx
	pop ebp
	ret
color_background ENDP

display_text_in_si_at_bp PROC
; eax returns: number of used bytes
	push esi
	push edi
	push ebx

	mov edi, ebp
	mov bl, cs:text_color
	write_text:
		mov al, cs:[si]
		cmp al, 0
		je end_of_text
		inc si
		mov es:[bp], al
		mov es:[bp + 1], bl
		add bp, 2
		jmp write_text

	end_of_text:
	add bp, 2
	mov eax, ebp
	sub eax, edi ; number of used bytes
	add eax, 2 ; the additional space

	pop ebx
	pop edi
	pop esi
	ret
display_text_in_si_at_bp ENDP

display_ax_at_bp PROC
; eax returns: number of used bytes
	push edx
	push edi
	push esi
	push ecx

	mov di, bp
	cmp ax, 0
	jge dodatnia
	neg ax
	mov cl, cs:text_color
	mov es:[bp], byte ptr '-'
	mov es:[bp + 1], cl
	add bp, 2

	dodatnia:
	mov cx, 0
	mov bx, 10

	divide:
		mov edx, 0
		div bx

		add dl, '0'
		push dx

		inc cx
		cmp eax, 0
		jne divide
	
	mov bl, cs:text_color
	write_num:
		pop dx
		mov es:[bp], dl
		mov es:[bp + 1], bl
		add bp, 2
		loop write_num

	mov ax, bp ; number of used bytes
	sub ax, di

	pop ecx
	pop esi
	pop edi
	pop edx
	ret
display_ax_at_bp ENDP

generate_new_random_number PROC
	rol ax, 7            
	xor ax, 0CDEFH
	mov bx, cs:last_scaling_random_factor
	add bx, 213H
	ror bx, 2
	sub bx, 9285H
	rol bx, 12
	mov cs:last_scaling_random_factor, bx
	add ax, 5432H
	ror ax, 4 
	rcl ax, 13       
	add ax, 047AH 
	mov bx, cs:last_scaling_random_factor
	add bx, 213H
	ror bx, 2
	sub bx, 9285H
	rol bx, 12
	mov cs:last_scaling_random_factor, bx
	mul bx
	ror ax, 5           
	sub ax, 0DA43H    
	rcl ax, 9          
	
	cmp ax, 64000     
	jbe skip_capping  
	sub ax, 48000     
	skip_capping:
	ret
generate_new_random_number ENDP

start:
	mov ah, 0
	mov al, 13H
	int 10H ; set VGA mode
	mov bx, 0
	mov es, bx
	mov eax, es:[32]
	mov cs:clock_handler_address, eax;
	push es

	mov esi, 0 ; y
	mov edi, 0 ; x
	mov ax, 0A000H
	mov es, ax

	mov edx, 0

	call color_background

	movzx cx, cs:snake_size
	mov edi, 0
	initialize_snake:
		mov eax, cs:snake_initial_pos
		sub eax, edi
		mov cs:pos_previous[edi * 2], ax
		inc edi
		mov bl, cs:snake_color
		mov ebp, eax
		mov es:[ebp], bl
		loop initialize_snake

	mov bp, cs:apple_initial_pos
	mov bl, cs:apple_color
	mov es:[bp], bl
	mov si, 0
	mov bp, cs:apple_initial_pos
	spawn_cluster_apples:
		add ebp, 1 
		mov cs:apple_positions[si], bp
		mov bl, cs:apple_color
		mov es:[bp], bl
		add si, 2
		cmp si, cluster_apple_count * 2
		jb spawn_cluster_apples
	spawn_apples_random:
		call generate_new_random_number
		mov bp, ax
		mov cs:apple_positions[si], bp
		mov bl, cs:apple_color
		mov es:[bp], bl
		add si, 2
		cmp si, apple_count * 2
		jb spawn_apples_random

	next2:
	pop es
	mov ax, SEG update_snake
	mov bx, OFFSET update_snake
	cli
	mov es:[32], bx
	mov es:[32+2], ax
	sti
	wait_for_input:
	mov ah, 1
	int 16h ; get keyboard buffer state
	jz wait_for_input
	; read key
	in al, 60H
	cmp al, 17 ; W
	je w_pressed
	cmp al, 31 ; S
	je s_pressed
	cmp al, 30 ; A
	je a_pressed
	cmp al, 32 ; D
	je d_pressed
	cmp al, 20 ; T - text debug print mode
	je t_pressed
	cmp al, 47 ; V - video mode
	je v_pressed
	cmp al, 34 ; G - pause snake
	je g_pressed
	cmp al, 35 ; H - pause pong
	je h_pressed
	cmp al, 45 ; X - exit
	jne wait_for_input
	jmp zakoncz

	w_pressed:
		mov cs:last_direction, -320
		mov cs:dir_previous, -320
		mov cs:racket1_y_dir, -1
		jmp wait_for_input

	s_pressed:
		mov cs:last_direction, 320
		mov cs:dir_previous, 320
		mov cs:racket1_y_dir, 1
		jmp wait_for_input

	a_pressed:
		mov cs:last_direction, -1
		mov cs:dir_previous, -1
		jmp wait_for_input

	d_pressed:
		mov cs:last_direction, 1
		mov cs:dir_previous, 1
		jmp wait_for_input

	t_pressed:
		mov cs:is_pong_game_paused, 1
		mov ah, 0
		mov al, 03H
		int 10H

		mov ax, 0B800H
		mov es, ax
		mov bp, 78 + 160
		mov bl, cs:game_title_text_color
		mov es:[bp], byte ptr 'P'
		mov es:[bp + 1], bl
		mov es:[bp + 2], byte ptr 'O'
		mov es:[bp + 3], bl
		mov es:[bp + 4], byte ptr 'N'
		mov es:[bp + 5], bl
		mov es:[bp + 6], byte ptr 'G'
		mov es:[bp + 7], bl

		add bp, 160 * 2
		sub bp, 70
		push esi
		push edi
		mov si, OFFSET cs:txt_ball_speed_x
		call display_text_in_si_at_bp
		mov edi, eax
		mov ax, cs:ball_speed_x
		call display_ax_at_bp
		sub bp, ax
		sub bp, di
		add bp, 160
		mov si, OFFSET cs:txt_ball_speed_y
		call display_text_in_si_at_bp
		mov edi, eax
		mov ax, cs:ball_speed_y
		call display_ax_at_bp
		sub bp, ax
		sub bp, di
		add bp, 160
		mov si, OFFSET cs:txt_ball_pos_x
		call display_text_in_si_at_bp
		mov edi, eax
		mov ax, cs:ball_pos_x
		call display_ax_at_bp
		sub bp, ax
		sub bp, di
		add bp, 160
		mov si, OFFSET cs:txt_ball_pos_y
		call display_text_in_si_at_bp
		mov edi, eax
		mov ax, cs:ball_pos_y
		call display_ax_at_bp
		sub bp, ax
		sub bp, di

		pop edi
		pop esi

		jmp wait_for_input
		
	v_pressed:
		mov cs:is_pong_game_paused, 0
		mov ah, 0
		mov al, 13H
		int 10H
		mov ax, 0A000H
		mov es, ax
		jmp wait_for_input

	g_pressed:
		mov dh, cs:is_snake_game_paused
		xor dh, 1
		mov cs:is_snake_game_paused, dh
		jmp wait_for_input

	h_pressed:
		mov dh, cs:is_pong_game_paused
		xor dh, 1
		mov cs:is_pong_game_paused, dh
		jmp wait_for_input

	zakoncz:
	mov ah, 0
	mov al, 3H
	int 10H

	mov eax, cs:clock_handler_address
	mov es:[32], eax
	mov ax, 4C00H
	int 21H
instr ENDS
stack SEGMENT stack
db 256 dup (?)
stack ENDS
END start