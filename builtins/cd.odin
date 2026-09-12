package builtins

import "../src/jobs"
import "../src/reader"
import shell "../src/state"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

cd :: proc(p: ^jobs.Process, s: ^shell.ShellState) -> int {

	if len(p.expanded_args) == 2 {
		home, ok := s.vars["HOME"]
		if !ok {
			reader.render_error("HOME env is not set")
			return -1
		}
		posix.chdir(strings.clone_to_cstring(home, context.temp_allocator))
	} else if len(p.expanded_args) == 3 {
		if p.expanded_args[1] == "-" {
			reader.render_error(fmt.tprintf("cd: unsupported flag: %s", p.expanded_args[1]))
			return -1
		}
		res := posix.chdir(p.expanded_args[1])
		if res == .FAIL {
			msg := fmt.tprintf("cd: %s: No such file or directory", p.expanded_args[1])
			reader.render_error(msg)
			return -1
		}
	} else {
		reader.render_error(fmt.tprintf("cd: unsupported flag: %s", p.expanded_args[1]))
		return -1
	}


	delete(s.old_wd)
	s.old_wd = s.cwd
	cwd, err := os.get_working_directory(context.temp_allocator)
	if err == nil {
		s.cwd = strings.clone(cwd)
	}
	//TODO:update and add PWD and OLDPWD env vars

	return 0
}
