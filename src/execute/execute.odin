package execute

import "../jobs"
import "../parser"
import "../state"
import "core:c"
import "core:fmt"
import "core:strings"
import posix "core:sys/posix"


EventError :: enum {
	None,
	Fork_Error,
	Env_Error,
	Exec_Error,
}

// ExecStatus :: enum {
// 	Finished,
// 	Suspended,
// 	Stopped,
// 	Background,
// 	Failed,
// }

ExecEvent :: struct {
	// status: ExecStatus,
	err: EventError,
	job: ^jobs.Job,
	msg: string,
}


exec :: proc(cmd: parser.Command, s: ^state.ShellState) -> ExecEvent {
	return exec_list(cmd, s)
}

exec_list :: proc(cmd: parser.Command, s: ^state.ShellState) -> ExecEvent {
	j := new(jobs.Job)
	// j.command =  I don't have the original command as parser takes it so
	// either the cmd in passed to exec event or parser has to call the execute
	// so original string exists or parser has to return the string too as the
	// string might have error
	j.procs = make([dynamic]^jobs.Process)
	defer delete(j.procs)

	left, err := exec_cmd(cmd, s, j)
	if err != .None {
		return ExecEvent{err = err}
	}

	return ExecEvent{job = j}
}


exec_cmd :: proc(cmd: parser.Command, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	if s.is_interactive do state.disable_raw(s)
	defer if s.is_interactive do state.enable_raw(s)

	#partial switch c in cmd {
	case ^parser.IfClause:
		return exec_if(c, s, j)
	case:
		return exec_simple(c.(^parser.SimpleCommand), s, j)
	}
}


// exec_pipeline :: proc(cmd: parser.Command, s: ^state.ShellState) -> int {
// 	//execute a pipe line
// }

// execute :: proc(cmd: parser.Command, s: ^state.ShellState) -> ExecEvent {
// 	#partial switch c in cmd {
// 	case:
// 		return exec_simple(c.(^parser.SimpleCommand), s)
// 	}
// }

exec_if :: proc(c: ^parser.IfClause, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	cond, err := exec_cmd(c.condition, s, j)
	if err != .None {
		return 1, err
	}
	if (cond == 0) {
		exec, if_err := exec_cmd(c.then_branch, s, j)
		if if_err != .None {
			return 1, err
		}

		if exec == 0 {
			return 0, .None
		}
	}
	if c.else_branch == nil {
		return 1, .None
	}

	if type_of(c.else_branch) == ^parser.IfClause {
		return exec_if(c.else_branch.(^parser.IfClause), s, j)
	}
	return exec_cmd(c.else_branch, s, j)
}

@(private)
exec_simple :: proc(
	c: ^parser.SimpleCommand,
	s: ^state.ShellState,
	j: ^jobs.Job,
) -> (
	int,
	EventError,
) {
	p := new(jobs.Process) //this should be somewhere in exec_cmd()
	jobs.create_process(p, c)


	if len(j.procs) == 0 {
		p.is_first = true
	}

	append(&j.procs, p)


	err := spawn_process(p, j)
	if err != .None {
		return 1, err
	}

	if p.is_first {
		j.pgid = p.pid
	}

	if c.is_bg {
		j.is_bg = true
		return 0, .None
	}

	sid := posix.getpgrp()
	posix.setpgid(p.pid, j.pgid) //place the child in the job process group

	//Ignore terminal input and output so shell can take back the control
	posix.signal(.SIGTTOU, auto_cast posix.SIG_IGN)
	posix.signal(.SIGTTIN, auto_cast posix.SIG_IGN)

	posix.tcsetpgrp(posix.STDIN_FILENO, j.pgid) //handle the terminal to child
	exit_status := reap_process(p.pid)
	posix.tcsetpgrp(posix.STDIN_FILENO, sid) //take back the terminal

	p.exit_status = exit_status
	return exit_status, .None
}

@(private)
reap_process :: proc(pid: posix.pid_t) -> int {
	status: c.int
	posix.waitpid(pid, &status, {.UNTRACED, .CONTINUED})

	switch {
	case posix.WIFEXITED(status):
		return int(posix.WEXITSTATUS(status))
	case posix.WIFSIGNALED(status):
		return 128 + int(posix.WTERMSIG(status))
	case posix.WIFSTOPPED(status):
		return 128 + int(posix.WSTOPSIG(status))
	case:
		return 1
	}
}

@(private)
spawn_process :: proc(p: ^jobs.Process, j: ^jobs.Job) -> (err: EventError) {
	pid := posix.fork()
	if pid == -1 {
		return .Fork_Error
	}
	if pid == 0 {
		child_setup(p, j)
		posix.execvp(p.cmd, raw_data(p.args))
		posix.exit(127) //may not need this
	}
	p.pid = pid
	return .None
}

@(private)
child_setup :: proc(p: ^jobs.Process, j: ^jobs.Job) {
	child_pid := posix.getpid()

	if p.is_first {
		posix.setpgid(child_pid, child_pid)
		j.pgid = child_pid
	} else {
		posix.setpgid(child_pid, j.pgid)
	}

	if !j.is_bg {
		posix.signal(.SIGTTOU, auto_cast posix.SIG_IGN)
		posix.tcsetpgrp(posix.STDIN_FILENO, j.pgid)
	}

	reset_signal()

	for r in p.redirects {
		file_path := strings.clone_to_cstring(r.file)
		defer delete(file_path)

		flags: posix.O_Flags
		mode: posix.mode_t = {.IRUSR, .IWUSR, .IRGRP, .IROTH}

		#partial switch r.kind {
		case .GREATER:
			flags = {.WRONLY, .CREAT, .TRUNC}
		case .DGREAT:
			flags = {.WRONLY, .CREAT, .APPEND}
		}

		fd := posix.open(file_path, flags, mode)
		defer posix.close(fd)
		if fd < 0 {
			posix.exit(1)
		}
		if posix.dup2(fd, posix.FD(r.fd)) < 0 {
			posix.exit(1)
		}
	}

	for k, v in p.env {
		if posix.setenv(k, v, true) != .OK {
			continue
		}
	}

}

@(private)
reset_signal :: proc() {
	signals := []posix.Signal{.SIGINT, .SIGQUIT, .SIGTSTP, .SIGTTIN, .SIGTTOU}
	for sig in signals {
		posix.signal(sig, auto_cast posix.SIG_DFL)
	}
}

//use sigaction and register a sigchild handler for this
reap_bg_processes :: proc(s: ^state.ShellState) {
	status: c.int
	found: bool
	completed_id: int

	for {
		wait_pid := posix.waitpid(-1, &status, {.NOHANG})
		if wait_pid <= 0 do break

		if posix.WIFEXITED(status) || posix.WIFSIGNALED(status) {
			for id, pid in s.bg_processes {
				if pid == wait_pid {
					completed_id = id
					found = true
					break
				}
			}

			if found {
				fmt.printf("[%d]-done\n", (completed_id + 1))
				delete_key(&s.bg_processes, completed_id)
			}
		}
	}
}

