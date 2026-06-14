package reader
import "core:fmt"
import "core:io"
import "core:os"
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

Input :: union {
	rune,
	Key,
}


//error handling
read_key :: proc(stream: io.Stream) -> Input {

	ch, sz, err := io.read_rune(stream)

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


CursorControl :: [Cursor]string {
	.ClearScreen = CSI + "2J",
	.ClearLine   = CSI + "2K",
	.Home        = CSI + "H",
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

reader_fini :: proc(r: ^ReaderState) {
	delete(r.buffer)
	free(r)
}

read_line :: proc(r: ^ReaderState) -> string {
	clear(&r.buffer)
	r.cursor_pos = 0
	stream := os.to_stream(os.stdin)
	read(r, stream)

	return utf8.runes_to_string(r.buffer[:], context.temp_allocator)

}

@(private)
read :: proc(r: ^ReaderState, stream: io.Stream) {
	render :: proc(r: ^ReaderState, stream: io.Stream) {

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

		io.write(stream, sb.buf[:])


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

		io.write_string(stream, "\r\n")

		clear(&r.buffer)
		r.cursor_pos = 0

		render(r, stream)
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


	render(r, stream)
	for {
		key := read_key(stream)

		switch v in key {
		case rune:
			add_to_buffer(r, v)
			render(r, stream)
		case Key:
			#partial switch v {
			case .Ctrl_C:
				handle_ctrlc(r, stream)
			case .Ctrl_L:
				io.write_string(stream, CursorControl[.ClearScreen])
				io.write_string(stream, CursorControl[.Home])

				render(r, stream)
			case .Enter:
				io.write_string(stream, "\n")
				return
			case .BackSpace:
				delete_from_buffer(r)
				render(r, stream)
			case .Tab:
			//how to handle this?
			//TODO:add searching for binaries and show them?
			case .Ctrl_W:
				delete_word(r)
				render(r, stream)
			case .Left_Arrow:
				move_left(r)
				render(r, stream)
			case .Right_Arrow:
				move_right(r)
				render(r, stream)
			// case .Up_Arrow:
			// //history up                //TODO:Add histories
			// case .Down_Arrow:
			// //history down
			}
		}

	}
}

