package jobs

import "core:strings"
import "core:unicode"

import "../parser"
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

destroy_process :: proc(p: ^Process) {
	for k, v in p.env {
		delete(k)
		delete(v)
	}
	delete(p.env)
	for arg in p.args {
		delete(arg)
	}
	delete(p.args)
	for e in p.expanded_args {
		delete(e)
	}
	delete(p.expanded_args)
	for r in p.redirects {
		delete(r.file)
	}
	delete(p.redirects)

	free(p)
}

populate_process :: proc(
	vars: map[string]string,
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

	p.args = make([dynamic]string, 0, len(cmd.words))
	for w in cmd.words {
		append(&p.args, strings.clone(w))
	}
	args := expand_env(vars, cmd.words)
	p.expanded_args = args
	p.cmd = args[0]
	return nil
}


//TODO:parameter expansion
expand_env :: proc(vars: map[string]string, words: [dynamic]string) -> (args: [dynamic]cstring) {
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
		val, ok := vars[a[idx + 1:offset]]
		replaced_string: string
		if ok {
			replaced_string, _ = strings.replace(a, a[idx:offset], val, -1)
		} else {
			replaced_string, _ = strings.replace(a, a[idx:offset], "", 1)
		}
		append(&args, strings.clone_to_cstring(replaced_string))
		delete(replaced_string)
	}
	append(&args, nil)
	return args
}
