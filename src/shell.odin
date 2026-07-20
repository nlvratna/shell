package shell

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import posix "core:sys/posix"
import "execute"
import "parser"
import "reader"

BuiltinProc :: proc(s: ^ShellState) -> int

TermState :: struct {
	termios: posix.termios,
	//TODO: add window dimensions
}

ShellState :: struct {
	arena:            virtual.Arena,
	binaries:         [dynamic]string,
	builtins:         map[string]BuiltinProc,
	is_running:       bool,
	is_interactive:   bool,
	cwd:              string,
	old_wd:           string,
	using term_state: TermState,
	prompt:           string,
}


shell_state_init :: proc(s: ^ShellState) {
	err := virtual.arena_init_growing(&s.arena)
	if err != nil {
		panic("couldn't allocate memory")
	}
	s.is_running = true
	s.prompt = "$ "

	cd, alloc_err := os.get_working_directory(context.temp_allocator)
	if alloc_err == nil {
		s.cwd = cd
	}

	//TODO: set binaries and builtins
	s.binaries = make([dynamic]string)
	s.builtins = make(map[string]BuiltinProc)
}

shell_state_destroy :: proc(s: ^ShellState) {
	virtual.arena_destroy(&s.arena)
	delete(s.binaries)
	delete(s.builtins)
}

run :: proc {
	run_interactive,
	run_not_interactive,
}


@(private = "file")
run_not_interactive :: proc(s: ^ShellState, data: string) {
	defer free_all(context.allocator)
	p: parser.Parser //TODO:the file will have a bang at the start have to include that
	parser.parser_init(&p, data)
	program, err := parser.parse(&p)
	if err != nil {
		err_msg := fmt.tprintf("The error:%v", err) //todo:this will be changed
		reader.render_error(err_msg)
	}
	execute.execute(program)
}


@(private = "file")
run_interactive :: proc(s: ^ShellState) {
	r: reader.ReaderState
	reader.reader_init(&r, s.prompt)

	for {
		data := reader.read_line(&r)

		context.allocator = virtual.arena_allocator(&s.arena)
		defer free_all(context.allocator)
		defer free_all(context.temp_allocator)

		p: parser.Parser
		parser.parser_init(&p, data)

		program, err := parser.parse(&p)
		if err != nil {
			err_msg := fmt.tprintf("The error:%v", err) //todo:this will be changed
			reader.render_error(err_msg)
		}

		execute.execute(program)
	}
}


enable_raw :: proc(s: ^ShellState) {
	result := posix.tcgetattr(posix.STDIN_FILENO, &s.termios)
	assert(result == .OK)

	raw := s.termios
	raw.c_iflag -= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
	raw.c_lflag -= {.ECHO, .ICANON, .IEXTEN, .ISIG}
	raw.c_cc[.VMIN] = 1
	raw.c_cc[.VTIME] = 0

	result = posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw)
	assert(result == .OK)


}

disable_raw :: proc(s: ^ShellState) {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &s.termios)
}

