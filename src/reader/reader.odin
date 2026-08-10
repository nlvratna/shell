package reader
import "core:fmt"
import "core:io"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"


ESC :: "\x1b"
CSI :: ESC + "["

Cursor :: enum {
	ClearScreen,
	ClearLine,
	Home,
}

CursorControl :: [Cursor]string {
	.ClearScreen = CSI + "2J",
	.ClearLine   = CSI + "2K",
	.Home        = CSI + "H",
}

Key :: enum {
	Ctrl_A,
	Ctrl_C,
	Ctrl_D,
	Ctrl_L,
	Ctrl_W,
	BackSpace,
	Tab,
	Enter,
	Escape,


	//Arrow Keys
	Left_Arrow,
	Right_Arrow,
	Up_Arrow,
	Down_Arrow,


	//
	Unknown,
}

ReadError :: struct {
	msg: string,
}

Input :: union {
	rune,
	Key,
	ReadError,
}

InputEventType :: enum {
	None,
	Line_Ready,
	Read_Error,
	Exit_Shell,
	SigChld,
	SigWhich,
}

InputEvent :: struct {
	type: InputEventType,
	data: string,
	err:  string,
}

//error handling
read_key :: proc(stream: io.Stream) -> Input {
	ch, sz, err := io.read_rune(stream)
	if err != nil {
		err_msg := fmt.tprintf("Read error:%v", err)
		return ReadError{msg = err_msg}
	}

	switch ch {
	case 1:
		return .Ctrl_A
	case 3:
		return .Ctrl_C
	case 4:
		return .Ctrl_D
	case 12:
		return .Ctrl_L
	case 8, 127:
		return .BackSpace
	case 9:
		return .Tab
	case 10, 13:
		return .Enter
	case 23:
		return .Ctrl_W
	case 27:
		second, size, err := io.read_rune(stream)

		if second == '[' {
			third, size, err := io.read_rune(stream)

			switch third {
			case 'A':
				return .Up_Arrow
			case 'B':
				return .Down_Arrow
			case 'C':
				return .Right_Arrow
			case 'D':
				return .Left_Arrow

			}

		}

	case 32 ..= 126, 128 ..= 0x10FFFF:
		return ch
	}
	return .Unknown
}


ReaderState :: struct {
	buffer:     [dynamic]rune,
	cursor_pos: int,
	prompt:     string,
	prompt_len: int,
}

reader_init :: proc(r: ^ReaderState, prompt: string) -> ^ReaderState {
	r^ = ReaderState {
		buffer     = make([dynamic]rune),
		cursor_pos = 0,
		prompt     = prompt,
		prompt_len = len(prompt),
	}
	return r
}

reader_destroy :: proc(r: ^ReaderState) {
	delete(r.buffer)
	free(r)
}

clear_buf :: proc(r: ^ReaderState) {
	clear(&r.buffer)
	r.cursor_pos = 0
}

clear_screen :: proc() {
	render(CursorControl[.ClearScreen] + CursorControl[.Home]) //clean the screen at startup and place cursor at home
}

read_line :: proc(r: ^ReaderState, stream: io.Stream) -> InputEvent {
	type := read(r, stream)

	data := utf8.runes_to_string(r.buffer[:], context.temp_allocator)

	if type == .Read_Error {
		return InputEvent{err = data, type = type}
	} else if type == .Line_Ready {
		return InputEvent{data = data, type = type}
	} else if type == .Exit_Shell {
		return InputEvent{type = type}
	}
	return InputEvent{type = type}

}

@(private)
read :: proc(r: ^ReaderState, stream: io.Stream) -> InputEventType {

	print :: proc(r: ^ReaderState) {

		sb: strings.Builder
		strings.builder_init(&sb, context.temp_allocator)
		defer strings.builder_destroy(&sb)

		strings.write_string(&sb, "\r")
		strings.write_string(&sb, CursorControl[.ClearLine])

		strings.write_string(&sb, r.prompt)

		for ch in r.buffer {
			strings.write_rune(&sb, ch)
		}

		cursor_col := r.prompt_len + r.cursor_pos + 1
		fmt.sbprintf(&sb, "%s%dG", CSI, cursor_col)

		render(sb.buf[:])
	}

	delete_from_buffer :: proc(r: ^ReaderState) {
		if len(r.buffer) == 0 {
			return
		}
		ordered_remove(&r.buffer, r.cursor_pos - 1)
		r.cursor_pos -= 1
	}

	add_to_buffer :: proc(r: ^ReaderState, ch: rune) {
		if r.cursor_pos == len(r.buffer) {
			append(&r.buffer, ch)
		} else {
			inject_at(&r.buffer, r.cursor_pos, ch)
		}
		r.cursor_pos += 1
	}

	add_string :: proc(r: ^ReaderState, data: string) {
		for ch in data {
			add_to_buffer(r, ch)
		}
	}

	delete_word :: proc(r: ^ReaderState) {
		if len(r.buffer) == 0 || r.cursor_pos == 0 {
			return
		}

		curr_pos := r.cursor_pos - 1

		for curr_pos >= 0 && unicode.is_white_space(r.buffer[curr_pos]) {
			ordered_remove(&r.buffer, curr_pos)
			curr_pos -= 1
		}

		for curr_pos >= 0 && !unicode.is_white_space(r.buffer[curr_pos]) {
			ordered_remove(&r.buffer, curr_pos)
			curr_pos -= 1
		}
		r.cursor_pos = curr_pos + 1
	}


	handle_ctrlc :: proc(r: ^ReaderState, stream: io.Stream) {
		render("\r\n")
		clear_buf(r)
		print(r)
	}

	handle_ctrld :: proc(r: ^ReaderState) -> InputEventType {
		if len(r.buffer) == 0 {
			return .Exit_Shell
		}
		return .None
	}


	move_left :: proc(r: ^ReaderState) {
		if r.cursor_pos == 0 {
			return
		}
		r.cursor_pos -= 1
	}


	move_right :: proc(r: ^ReaderState) {
		if r.cursor_pos == 0 && len(r.buffer) == 0 {
			return
		}
		if r.cursor_pos == len(r.buffer) {
			return
		}
		r.cursor_pos += 1
	}

	// clear_buf(r)
	print(r)
	for {
		key := read_key(stream)

		switch v in key {
		case ReadError:
			add_string(r, v.msg)
			return .Read_Error
		case rune:
			add_to_buffer(r, v)
			print(r)
		case Key:
			#partial switch v {
			case .Ctrl_C:
				handle_ctrlc(r, stream)
			case .Ctrl_D:
				return handle_ctrld(r)
			case .Ctrl_L:
				render(CursorControl[.ClearScreen] + CursorControl[.Home])
				print(r)
			case .Enter:
				render("\n")
				return .Line_Ready
			case .BackSpace:
				delete_from_buffer(r)
				print(r)
			case .Tab:
			//how to handle this?
			//TODO:add searching for binaries and show them?
			case .Ctrl_W:
				delete_word(r)
				print(r)
			case .Left_Arrow:
				move_left(r)
				print(r)
			case .Right_Arrow:
				move_right(r)
				print(r)
			// case .Up_Arrow:
			// //history up                //TODO:Add histories
			// case .Down_Arrow:
			// //history down
			}
		}

	}
}

