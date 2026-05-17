package reader

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

import posix "core:sys/posix"

ESC :: "\x1b"
CSI :: ESC + "["

clear_screen := CSI + "2J"
cursor_home := CSI + "H"

ReaderState :: struct {
	buffer:     [dynamic]rune,
	cursor_pos: int,
	prompt:     string,
	prompt_len: int,
}

read_line :: proc(prompt: string) -> string {

	r := ReaderState{make([dynamic]rune), 0, prompt, len(prompt)}

	if (!posix.isatty(posix.STDIN_FILENO)) {
		//read from file
	}
	enable_raw_mode()
	defer disable_raw_mode()

	read(&r)

	return utf8.runes_to_string(r.buffer[:])

}

read :: proc(r: ^ReaderState) {
	stream := os.to_stream(os.stdin)
	render(r, stream)
	for {
	}
}

render :: proc(r: ^ReaderState, stream: io.Stream) {

	io.write(stream, transmute([]byte)cursor_home)
	io.write(stream, transmute([]byte)clear_screen)
	io.write(stream, transmute([]byte)r.prompt)
	//move cursor to prompt+len
	sb: strings.Builder
	st := fmt.sbprintf(&sb, "%s%dG", CSI, r.prompt_len)
	io.write(stream, transmute([]byte)st)


}

