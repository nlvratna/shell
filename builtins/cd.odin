package builtins

import "../src/jobs"
import shell "../src/state"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

cd :: proc(p: ^jobs.Process, s: ^shell.ShellState) -> (int, string) {

	if len(p.expanded_args) == 2 {
		home, ok := s.vars["HOME"]
		if !ok {
			return -1, "HOME env is not set"
		}
		posix.chdir(strings.clone_to_cstring(home, context.temp_allocator))
	} else if len(p.expanded_args) == 3 {
		if p.expanded_args[1] == "-" {
			return -1, fmt.tprintf("cd: unsupported flag: %s", p.expanded_args[1])

		}
		res := posix.chdir(p.expanded_args[1])
		if res == .FAIL {
			msg := fmt.tprintf("cd: %s: No such file or directory", p.expanded_args[1])
			return -1, msg

		}
	} else {
		return -1, fmt.tprintf("cd: unsupported flag: %s", p.expanded_args[1])

	}


	delete(s.old_wd)
	s.old_wd = s.cwd
	cwd, err := os.get_working_directory(context.temp_allocator)
	if err == nil {
		s.cwd = strings.clone(cwd)
	}
	//TODO:update and add PWD and OLDPWD env vars

	return 0, ""
}
