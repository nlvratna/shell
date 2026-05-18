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
read_line :: proc(r: ^ReaderState) -> string {

	if (!posix.isatty(posix.STDIN_FILENO)) {
		//read from file
	}
	enable_raw_mode()
	defer disable_raw_mode()

	read(r)

	return utf8.runes_to_string(r.buffer[:])

}

read :: proc(r: ^ReaderState) {
	stream := os.to_stream(os.stdin)
	render(r, stream)
	for {
		ch, size, err := io.read_rune(stream)

		switch {
		case err != nil:
			if err == .EOF {
				break
			}
			continue
		case:
			append(&r.buffer, ch)
			r.cursor_pos += 1
			render(r, stream)

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

