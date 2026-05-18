package reader

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

import posix "core:sys/posix"

ESC :: "\x1b"
CSI :: ESC + "["

Cursor :: enum {
	ClearScreen,
	Home,
}

Key :: enum {
	Ctrl_A,
	Ctrl_C,
	Ctrl_D,
	Ctrl_L,
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
	.Home        = CSI + "H",
}


ReaderState :: struct {
	buffer:     [dynamic]rune,
	cursor_pos: int,
	prompt:     string,
	prompt_len: int,
}

reader_ini :: proc(r: ^ReaderState, prompt: string) {
	r^ = ReaderState{make([dynamic]rune), 0, prompt, len(prompt)}
}

reader_fini :: proc(r: ^ReaderState) {
	delete(r.buffer)
}
read_line :: proc(r: ^ReaderState, stream: io.Stream) -> string {

	if (!posix.isatty(posix.STDIN_FILENO)) {
		//read from file
	}
	enable_raw_mode()
	defer disable_raw_mode()

	read(r, stream)

	return utf8.runes_to_string(r.buffer[:])

}

read :: proc(r: ^ReaderState, stream: io.Stream) {
	render(r, stream)
	for {
		key := read_key(stream)

		switch v in key {
		case rune:
			if v == 'q' {
				os.exit(1) //for now
			}
			add_to_buffer(r, v)
			render(r, stream)
		case Key:
		}

	}
}

@(private)
render :: proc(r: ^ReaderState, stream: io.Stream) {

	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	strings.write_string(&sb, CursorControl[.Home])
	strings.write_string(&sb, CursorControl[.ClearScreen])

	strings.write_string(&sb, r.prompt)

	for ch in r.buffer {
		strings.write_rune(&sb, ch)
	}

	cursor_col := r.prompt_len + r.cursor_pos + 1
	fmt.sbprintf(&sb, "%s%dG", CSI, cursor_col)

	io.write(stream, sb.buf[:])


}

@(private = "file")
add_to_buffer :: proc(r: ^ReaderState, ch: rune) {
	if r.cursor_pos == len(r.buffer) {
		append(&r.buffer, ch)
	} else {
		inject_at(&r.buffer, r.cursor_pos, ch)
	}
	r.cursor_pos += 1
}

