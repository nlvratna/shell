package execute

import "../parser"
import "../state"
import "core:c"
import "core:fmt"
import "core:strings"
import posix "core:sys/posix"


execute :: proc(program: parser.Program, s: ^state.ShellState) {
	for cmd in program.cmds {
		#partial switch _ in cmd {
		case ^parser.SimpleCommand:
			exec_cmd(cmd.(^parser.SimpleCommand), s)
		}
	}
}


@(private)
exec_cmd :: proc(cmd: ^parser.SimpleCommand, s: ^state.ShellState) -> int {
	reset_signal :: proc() {
		signals := []posix.Signal{.SIGINT, .SIGQUIT, .SIGTSTP, .SIGTTIN, .SIGTTOU}

		for sig in signals {
			posix.signal(sig, auto_cast posix.SIG_DFL)
		}
	}

	state.disable_raw(s)

	shell_gpid := posix.getpgrp()
	pid := posix.fork()

	if pid == 0 {
		child_pid := posix.getpid()
		posix.setpgid(0, 0)

		if !cmd.is_bg {
			//TODO:handle the zombie process
			posix.signal(.SIGTTOU, auto_cast posix.SIG_IGN)
			posix.tcsetpgrp(posix.STDIN_FILENO, child_pid)
		}

		reset_signal() //reset the signal for the child process

		for r in cmd.redirects {
			file_path := strings.clone_to_cstring(r.file)
			defer delete(file_path)

			flags: posix.O_Flags
			mode: posix.mode_t = {.IRUSR, .IWUSR, .IRGRP, .IROTH}

			#partial switch r.kind {
			case .LESS:
				flags = {.RDWR}
			case .GREATER:
				flags = {.WRONLY, .CREAT, .TRUNC}
			case .DGREAT:
				flags = {.WRONLY, .CREAT, .APPEND}
			}

			file_fd := posix.open(file_path, flags, mode)
			defer posix.close(file_fd)

			if file_fd < 0 {
				posix.perror("shell:redirection error failed") //sends events accordignly to handle don't exit here
				posix.exit(1)
			}

			if posix.dup2(file_fd, auto_cast r.fd) < 0 {
				posix.perror("shell:dup2 redirection failed")
				posix.exit(1)
			}
		}

		for assign in cmd.assigns {
			idx := strings.index_byte(assign, '=')
			if idx == -1 do continue
			key := strings.clone_to_cstring(assign[:idx])
			defer delete(key)
			val := strings.clone_to_cstring(assign[idx + 1:])
			defer delete(val)

			if posix.setenv(key, val, true) != .OK {
				posix.perror("shell:cannot set key value")
			}
		}

		if len(cmd.words) > 0 {
			args := make([]cstring, len(cmd.words) + 1, context.temp_allocator)

			for word, i in cmd.words {
				args[i] = strings.clone_to_cstring(word)
			}
			args[len(cmd.words)] = nil

			posix.execvp(args[0], &args[0])
			posix.perror("shell: exec failed") //same do
			posix.exit(127)
		}
	} else if pid > 0 {
		defer state.enable_raw(s)

		if (cmd.is_bg) {
			fmt.printf("[Background Job Started]PID:%d\n", pid)
			return 0
		}

		posix.setpgid(pid, pid)

		//Ignore terminal input and output so shell can take back the control
		posix.signal(.SIGTTOU, auto_cast posix.SIG_IGN)
		posix.signal(.SIGTTIN, auto_cast posix.SIG_IGN)

		posix.tcsetpgrp(posix.STDIN_FILENO, pid) //handle the terminal to child

		status: c.int

		posix.waitpid(pid, &status, {.UNTRACED, .CONTINUED})

		posix.tcsetpgrp(posix.STDIN_FILENO, shell_gpid)

		switch {
		case posix.WIFEXITED(status):
			return int(posix.WEXITSTATUS(status))
		case posix.WIFSIGNALED(status):
			return 128 + int(posix.WTERMSIG(status))
		case posix.WIFSTOPPED(status):
			fmt.printf("\n[Job %d suspended]\n", pid)
			return 128 + int(posix.WSTOPSIG(status))
		case:
			return 1
		}
	}
	posix.perror("shell:fork failed")
	return 1
}

