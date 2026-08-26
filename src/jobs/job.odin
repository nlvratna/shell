package jobs

import "core:strings"
import posix "core:sys/posix"

Job :: struct {
	id:          int,
	pgid:        posix.pid_t,
	command:     string,
	procs:       [dynamic]^Process,
	is_bg:       bool,
	is_pipe:     bool,
	stdin:       posix.FD,
	stdout:      posix.FD,
	stderr:      posix.FD,
	remove_pipe: posix.FD,
}

init_job :: proc(j: ^Job, cmd: string) {
	j.command = strings.clone(cmd)
	j.stdin = posix.FD(posix.STDIN_FILENO)
	j.stdout = posix.FD(posix.STDOUT_FILENO)
	j.stderr = posix.FD(posix.STDERR_FILENO)
	j.procs = make([dynamic]^Process)

}

destroy_job :: proc(j: ^Job) {
	delete(j.command)
	for p in j.procs {
		destroy_process(p)
	}
	delete(j.procs)
	free(j)
}

