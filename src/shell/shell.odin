package shell

import "../execute"
import "../jobs"
import "../parser"
import "../reader"
import "../state"
import "core:fmt"
import "core:os"
import posix "core:sys/posix"


s: state.ShellState
rem_procs: map[posix.pid_t]^jobs.Process //store the process that are suspended or bg

init_shell :: proc() {
	state.shell_state_init(&s)
}

destroy_shell :: proc() {
	state.shell_state_destroy(&s)
}

// I don't think this is the right way to do it
run_not_interactive :: proc(data: string) {
	s.is_interactive = false

	defer free_all(context.temp_allocator)

	p: parser.Parser //TODO:the file will have a bang at the start have to include that
	parser.parser_init(&p, data)
	parser_event := parser.parse(&p)
	if parser_event.parse_event_type == .ErrorType {
		reader.render_error(parser_event.parse_err)
	}
	execute.exec(parser_event.command, &s)
}


run_interactive :: proc() {
	s.is_interactive = cast(bool)posix.isatty(posix.STDIN_FILENO)


	state.enable_raw(&s)
	defer state.disable_raw(&s)

	r: reader.ReaderState
	reader.reader_init(&r, s.prompt)

	for s.is_running {
		input_event := reader.read_line(&r, os.to_stream(os.stdin))
		defer reader.clear_buf(&r) //works even when an error occurs

		data: string
		#partial switch input_event.type {
		case .Line_Ready:
			data = input_event.data
		case .Read_Error:
			reader.render_error(input_event.err)
			continue
		case .Exit_Shell:
			state.disable_raw(&s)
			os.exit(0)
		}


		p: parser.Parser
		parser.parser_init(&p, data)

		parse_event := parser.parse(&p)
		if parse_event.parse_event_type == .ErrorType {
			//ask the user to enter the required token as bash,zsh does maybe
			reader.render_error(parse_event.parse_err)
			continue
		}
		defer free_all(context.temp_allocator) //free the ast

		// parser.print_ast(parse_event.command)
		exec := execute.exec(parse_event.command, &s)
		if exec.err != .None {
			reader.render_error(exec.msg)
			continue
		}
	}
}
