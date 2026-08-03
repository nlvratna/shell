package jobs

import "core:strings"
import "core:unicode"

import "../parser"
import "../state"
import posix "core:sys/posix"


ProcessErrorType :: enum {
	FileOpen_Error,
	Redirect_Error,
}


Process :: struct {
	pid:           posix.pid_t,
	id:            int,
	env:           map[cstring]cstring,
	cmd:           cstring,
	args:          [dynamic]string,
	expanded_args: [dynamic]cstring,
	redirects:     [dynamic]parser.Redirect, //this might not exist clone
	in_fd:         posix.FD,
	out_fd:        posix.FD,
	is_first:      bool, // is the first command in job
	is_last:       bool, // is the last command in job
	exit_status:   int,
}

init_process :: proc(p: ^Process, j: ^Job) {
	p.in_fd = j.stdin
	p.out_fd = j.stdout
}

populate_process :: proc(
	s: ^state.ShellState,
	p: ^Process,
	cmd: ^parser.SimpleCommand,
) -> ProcessErrorType {
	append(&p.redirects, ..cmd.redirects[:])
	p.env = make(map[cstring]cstring)
	for assign in cmd.assigns {
		idx := strings.index_byte(assign, '=')
		if idx == -1 do continue
		key := strings.clone_to_cstring(assign[:idx])
		val := strings.clone_to_cstring(assign[idx + 1:])

		p.env[key] = val
	}
	args := make([dynamic]cstring, 0, len(cmd.words) + 1)
	for w in cmd.words {
		append(&args, strings.clone_to_cstring(w))
	}
	append(&args, nil)
	p.cmd = args[0]
	p.args = cmd.words
	p.expanded_args = expand_env(s, cmd.words)
	return nil
}

//TODO:this is wrong change this
destroy_process :: proc(p: ^Process) {
	delete(p.args)
	delete(p.cmd)
	delete(p.env)
	delete(p.redirects)
	free(p)
}

//TODO:parameter expansion
//something is wrong here
expand_env :: proc(s: ^state.ShellState, words: [dynamic]string) -> (args: [dynamic]cstring) {
	args = make([dynamic]cstring)
	for arg in words {
		if arg == "" do continue

		a := string(arg)

		if strings.has_prefix(a, "'") && strings.has_suffix(a, "'") {
			append(&args, strings.clone_to_cstring(a[1:len(a) - 1]))
			continue
		}

		if strings.has_prefix(a, "\"") && strings.has_suffix(a, "\"") {
			a = a[1:len(a) - 1]
		}

		idx := strings.index_byte(a, '$')
		if idx == -1 {
			append(&args, strings.clone_to_cstring(a))
			continue
		}

		offset: int = idx + 1
		for len(a) > offset && unicode.is_alpha(rune(a[offset])) {
			offset = offset + 1
		}
		val, ok := s.vars[a[idx + 1:offset]]
		replaced_string: string
		if ok {
			replaced_string, _ = strings.replace(a, a[idx:offset], val, -1)
		} else {
			replaced_string, _ = strings.replace(a, a[idx:offset], "", 1)
		}
		append(&args, strings.clone_to_cstring(replaced_string))
	}
	append(&args, nil)
	return args
}
