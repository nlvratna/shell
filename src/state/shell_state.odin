package state

import "core:os"

import "core:mem/virtual"
import posix "core:sys/posix"


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

