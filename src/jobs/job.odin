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

