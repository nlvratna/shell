package execute

import "../jobs"
import "../parser"
import "../state"
import "base:runtime"
import "core:c"
import "core:strings"
import posix "core:sys/posix"


EventError :: enum {
	None,
	Break,
	Continue,
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


exec :: proc(cmd: parser.Command, s: ^state.ShellState, cmd_string: string) -> ExecEvent {
	j := new(jobs.Job)
	jobs.init_job(j, cmd_string)
	defer delete(j.procs)

	if s.is_interactive do state.disable_raw(s)
	defer if s.is_interactive do state.enable_raw(s)

	status, err := exec_cmd(cmd, s, j)
	if err != .None {
		return ExecEvent{err = err}
	}

	return ExecEvent{job = j}
}


exec_cmd :: proc(cmd: parser.Command, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	p := new(jobs.Process)
	jobs.init_process(p, j)

	if len(j.procs) == 0 {
		p.is_first = true
	}

	append(&j.procs, p)

	#partial switch c in cmd {
	case ^parser.IfClause:
		return exec_if(c, s, j)
	case ^parser.ForLoop:
		return exec_for(c, s, j)
	case ^parser.CommandList:
		return exec_cmdlist(c, s, j)
	case ^parser.Pipeline:
		return exec_pipe(c, s, j)
	case ^parser.WhileLoop:
		return exec_while(c, s, j)
	case ^parser.UntilLoop:
		return exec_until(c, s, j)
	case ^parser.CaseClause:
		return exec_case(c, s, j)
	case:
		return exec_simple(c.(^parser.SimpleCommand), s, j)
	}
}

//handle bang!
exec_pipe :: proc(c: ^parser.Pipeline, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	in_fd := posix.FD(posix.STDIN_FILENO)
	pipe_fds: [2]posix.FD

	j.is_pipe = true

	for i in 0 ..< len(c.commands) {
		cmd := c.commands[i]
		is_last := i == len(c.commands) - 1

		if !is_last {
			if posix.pipe(&pipe_fds) != .OK do return -1, .Exec_Error
		}

		j.stdin = in_fd
		j.stdout = is_last ? posix.STDOUT_FILENO : posix.FD(pipe_fds[1])
		j.remove_pipe = is_last ? posix.FD(-1) : posix.FD(pipe_fds[0])

		exec_cmd(cmd, s, j)

		if !is_last do posix.close(pipe_fds[1])
		if in_fd != posix.STDIN_FILENO do posix.close(in_fd)
		if !is_last do in_fd = pipe_fds[0]
	}

	j.is_pipe = false

	return wait_job(s, j), .None
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
	if len(c.words) == 0 {
		if len(c.assigns) == 1 {
			assign := c.assigns[0]
			idx := strings.index_byte(assign, '=')
			if idx == -1 do return 0, .None //this could be error
			key := strings.clone(assign[:idx])
			val := strings.clone(assign[idx + 1:])
			s.vars[key] = val
		}
		return 0, .None
	}

	p := j.procs[len(j.procs) - 1] //we are working with the last appended job
	jobs.populate_process(s, p, c)

	cmd_name := p.expanded_args[0]
	if cmd_name == "break" {
		jobs.destroy_process(p)
		return 0, .Break
	}
	if cmd_name == "continue" {
		jobs.destroy_process(p)
		return 0, .Continue
	}


	err := spawn_process(s, p, j)
	if err != .None {
		return -1, err
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

	if j.is_pipe {
		return 0, .None
	}
	return wait_job(s, j), .None
}


exec_if :: proc(c: ^parser.IfClause, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	cond, err := exec_cmd(c.condition, s, j)
	if err != .None {
		return -1, err
	}
	if (cond == 0) {
		exec_status, if_err := exec_cmd(c.then_branch, s, j)
		if if_err != .None {
			return -1, if_err
		}
		return exec_status, .None
	}

	if c.else_branch == nil {
		return -1, .None
	}

	if type_of(c.else_branch) == ^parser.IfClause {
		return exec_if(c.else_branch.(^parser.IfClause), s, j)
	}
	return exec_cmd(c.else_branch, s, j)
}


exec_cmdlist :: proc(
	c: ^parser.CommandList,
	s: ^state.ShellState,
	j: ^jobs.Job,
) -> (
	int,
	EventError,
) {
	left_status, left_err := exec_cmd(c.left, s, j)
	if left_err != .None {
		return left_status, left_err
	}

	if c.right == nil {
		return left_status, .None
	}

	#partial switch c.operator {
	case .ORIF:
		if left_status != 0 {
			return exec_cmd(c.right, s, j)
		}
		return left_status, .None
	case .ANDIF:
		if left_status == 0 {
			return exec_cmd(c.right, s, j)
		}
		return left_status, .None
	case .SEMICOLON:
		return exec_cmd(c.right, s, j)
	case:
		return left_status, .None
	}
}

//TODO : see if it possible to reduce the code redundancy
exec_for :: proc(c: ^parser.ForLoop, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	last_status: int
	for i in 0 ..< len(c.items) {
		s.vars[c.variable] = c.items[i]

		status, err := exec_cmd(c.body, s, j)

		last_status = status

		if err == .Break {
			break
		}
		if err == .Continue {
			continue
		}

		if err != .None {
			return status, err
		}
	}
	return last_status, .None
}

exec_while :: proc(c: ^parser.WhileLoop, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	last_status: int
	for {
		cond_stat, err := exec_cmd(c.condition, s, j)

		if err != .None || cond_stat != 0 {
			break
		}

		status, body_err := exec_cmd(c.body, s, j)
		last_status = status

		if body_err == .Break {
			break
		}

		if body_err == .Continue {
			continue
		}

		if body_err != .None {
			return status, body_err
		}

	}

	return last_status, .None
}

exec_until :: proc(c: ^parser.UntilLoop, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	for {
		cstat, err := exec_cmd(c.condition, s, j)

		if cstat == 0 {
			return cstat, .None
		}

		if err != .None {
			break
		}


		status, body_err := exec_cmd(c.body, s, j)

		if body_err == .Break {
			break
		}

		if body_err == .Continue {
			continue
		}

		if body_err != .None {
			return status, body_err
		}
	}
	return 0, .None // this is 0 as it exists when until command is satisfied
}

//TODO : expansion find a way for it
exec_case :: proc(c: ^parser.CaseClause, s: ^state.ShellState, j: ^jobs.Job) -> (int, EventError) {
	word := c.word

	if strings.has_prefix(word, "\"") && strings.has_suffix(word, "\"") {
		word = word[1:len(word) - 1]
	}

	if val, ok := s.vars[c.word]; ok {
		word = val
	}
	for item in c.items {
		for p in item.patterns {
			if word == p {
				return exec_cmd(item.body, s, j)
			} else if p == "*" {
				return exec_cmd(item.body, s, j)
			}
		}
	}
	return 1, .None
}

@(private)
reap_process :: proc(pid: posix.pid_t) -> int {
	status: c.int
	posix.waitpid(pid, &status, {.UNTRACED, .CONTINUED})

	switch {
	case posix.WIFEXITED(status):
		return int(posix.WEXITSTATUS(status))
	case posix.WIFSIGNALED(status):
		return -128 + int(posix.WTERMSIG(status))
	case posix.WIFSTOPPED(status):
		return -128 + int(posix.WSTOPSIG(status))
	case:
		return -1
	}
}

@(private)
spawn_process :: proc(s: ^state.ShellState, p: ^jobs.Process, j: ^jobs.Job) -> (err: EventError) {
	pid := posix.fork()
	if pid == -1 {
		return .Fork_Error
	}
	if pid == 0 {
		child_setup(p, j)
		set_redirects(p)
		posix.execvp(p.cmd, raw_data(p.expanded_args))
		// posix.exit(127) //may not need this command not found should not reach here I believe
	}
	p.pid = pid
	return .None
}

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

	if p.in_fd != posix.STDIN_FILENO {
		posix.dup2(p.in_fd, posix.STDIN_FILENO)
		posix.close(p.in_fd)
	}

	if p.out_fd != posix.STDOUT_FILENO {
		posix.dup2(p.out_fd, posix.STDOUT_FILENO)
		posix.close(p.out_fd)
	}

	if j.is_pipe && j.remove_pipe != -1 {
		posix.close(j.remove_pipe)
	}

}

@(private)
set_redirects :: proc(p: ^jobs.Process) {

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
wait_job :: proc(s: ^state.ShellState, j: ^jobs.Job) -> int {
	if j.is_bg {
		return 0
	}

	sid := posix.getpgrp()

	posix.signal(.SIGTTOU, auto_cast posix.SIG_IGN)
	posix.signal(.SIGTTIN, auto_cast posix.SIG_IGN)
	posix.tcsetpgrp(posix.STDIN_FILENO, j.pgid)

	exit_status := 0
	for p in j.procs {
		if p.pid > 0 {
			status := reap_process(p.pid)
			p.exit_status = status

			if p == j.procs[len(j.procs) - 1] {
				exit_status = status
			}
		}
	}

	// 3. Take terminal control back to the shell
	posix.tcsetpgrp(posix.STDIN_FILENO, sid)

	return exit_status
}

@(private)
reset_signal :: proc() {
	signals := []posix.Signal{.SIGINT, .SIGQUIT, .SIGTSTP, .SIGTTIN, .SIGTTOU}
	for sig in signals {
		posix.signal(sig, auto_cast posix.SIG_DFL)
	}
}

