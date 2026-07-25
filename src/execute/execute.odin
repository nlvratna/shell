package execute

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

ProcStatus :: enum {
	Finished,
	Suspended,
	Stopped,
	Background,
	Failed,
}

ExecEvent :: struct {
	status:  ProcStatus,
	err:     EventError,
	process: ^Process,
	msg:     string,
}


execute :: proc(cmd: parser.Command, s: ^state.ShellState) -> ExecEvent {
	#partial switch c in cmd {
	case:
		return exec_simple(c.(^parser.SimpleCommand), s)
	}
}

@(private)
exec_simple :: proc(c: ^parser.SimpleCommand, s: ^state.ShellState) -> ExecEvent {
	p := new(Process)
	create_process(p, c)

	if s.is_interactive do state.disable_raw(s)
	defer if s.is_interactive do state.enable_raw(s)

	pid, err := spawn_process(p)
	p.pid = pid
	if err != .None {
		return ExecEvent{err = err, msg = "fork failed"}
	}
	if p.is_bg {
		return ExecEvent{status = .Background, process = p}
	}

	sid := posix.getpgrp()
	posix.setpgid(pid, pid) //set shell and child in the same group

	//Ignore terminal input and output so shell can take back the control
	posix.signal(.SIGTTOU, auto_cast posix.SIG_IGN)
	posix.signal(.SIGTTIN, auto_cast posix.SIG_IGN)

	posix.tcsetpgrp(posix.STDIN_FILENO, pid) //handle the terminal to child
	res := reap_process(pid)
	posix.tcsetpgrp(posix.STDIN_FILENO, sid) //take back the terminal

	res.process = p

	if res.status == .Finished {
		destroy_process(p)
	}
	return res
}

@(private)
reap_process :: proc(pid: posix.pid_t) -> ExecEvent {
	status: c.int
	posix.waitpid(pid, &status, {.UNTRACED, .CONTINUED})

	switch {
	case posix.WIFEXITED(status):
		return ExecEvent{status = .Finished}
	case posix.WIFSIGNALED(status):
		return ExecEvent{status = .Stopped}
	case posix.WIFSTOPPED(status):
		return ExecEvent{status = .Suspended}
	case:
		return ExecEvent{status = .Failed}
	}
}

@(private)
spawn_process :: proc(p: ^Process) -> (pid: posix.pid_t, err: EventError) {
	pid = posix.fork()
	if pid == -1 {
		return -1, .Fork_Error
	}
	if pid == 0 {
		child_setup(p)
		posix.execvp(p.cmd, raw_data(p.args))
		posix.exit(127)
	}
	return pid, .None
}

@(private)
child_setup :: proc(p: ^Process) {
	child_pid := posix.getpid()
	p.pid = child_pid

	posix.setpgid(0, 0) // put child in its own process group

	if !p.is_bg {
		posix.signal(.SIGTTOU, auto_cast posix.SIG_IGN)
		posix.tcsetpgrp(posix.STDIN_FILENO, child_pid)
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
		if posix.dup2(fd, auto_cast r.fd) < 0 {
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

