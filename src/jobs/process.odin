package jobs

import "core:strings"

import "../parser"
import posix "core:sys/posix"


ProcessErrorType :: enum {
	FileOpen_Error,
	Redirect_Error,
}


Process :: struct {
	pid:         posix.pid_t,
	id:          int,
	env:         map[cstring]cstring,
	cmd:         cstring,
	args:        []cstring,
	redirects:   [dynamic]parser.Redirect, //this might not exist clone
	is_first:    bool, // is the first command in job
	is_last:     bool, // is the last command in job
	exit_status: int,
}

create_process :: proc(p: ^Process, cmd: ^parser.SimpleCommand) -> ProcessErrorType {
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
	p.args = args[:]
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
