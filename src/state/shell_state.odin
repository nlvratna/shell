package state

import "../jobs"
import "core:fmt"
import "core:os"

import posix "core:sys/posix"


BuiltinProc :: proc(s: ^ShellState) -> int

TermState :: struct {
	termios: posix.termios,
	//TODO: add window dimensions
}

ShellState :: struct {
	vars:             map[string]string,
	binaries:         [dynamic]string,
	builtins:         map[string]BuiltinProc,
	is_running:       bool,
	is_interactive:   bool,
	cwd:              string,
	old_wd:           string,
	using term_state: TermState,
	last_cmd_status:  int,
	bg_processes:     [dynamic]^jobs.Job,
	prompt:           string,
}


shell_state_init :: proc(s: ^ShellState) {
	s.is_running = true
	s.prompt = "$ "

	cwd, alloc_err := os.get_working_directory(context.temp_allocator)
	if alloc_err == nil {
		s.cwd = cwd
	} else {
		fmt.println("Error is here")
	}
	s.vars = make(map[string]string)
	//TODO: set binaries and builtins
	s.binaries = make([dynamic]string)
	s.builtins = make(map[string]BuiltinProc)


	result := posix.tcgetattr(posix.STDIN_FILENO, &s.termios)
	assert(result == .OK)
}

shell_state_destroy :: proc(s: ^ShellState) {
	for bin in s.binaries {
		delete(bin)
	}
	delete(s.binaries)
	for k in s.builtins {
		delete(k)
	}
	delete(s.builtins)

	for rem in s.bg_processes {
		jobs.destroy_job(rem) //is this good
	}
	delete(s.bg_processes)
}


enable_raw :: proc(s: ^ShellState) {
	raw := s.termios
	raw.c_iflag -= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
	raw.c_lflag -= {.ECHO, .ICANON, .IEXTEN, .ISIG}
	raw.c_cc[.VMIN] = 1
	raw.c_cc[.VTIME] = 0

	result := posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw)
	assert(result == .OK)
}

disable_raw :: proc(s: ^ShellState) {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &s.termios)
}

