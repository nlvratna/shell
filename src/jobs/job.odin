package jobs

import posix "core:sys/posix"

Job :: struct {
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
	j.command = cmd
	j.stdin = posix.FD(posix.STDIN_FILENO)
	j.stdout = posix.FD(posix.STDOUT_FILENO)
	j.stderr = posix.FD(posix.STDERR_FILENO)
	j.procs = make([dynamic]^Process)

}

