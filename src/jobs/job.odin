package jobs

import posix "core:sys/posix"

Job :: struct {
	pgid:    posix.pid_t,
	command: string,
	procs:   [dynamic]^Process,
	is_bg:   bool,
}

