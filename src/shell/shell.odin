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
	// if parser_event.parse_event_type == .ErrorType {
	// 	reader.render_error(parser_event.parse_err)
	// }
	execute.exec(parser_event.command, &s, parser_event.cmd_string)
}


run_interactive :: proc() {
	curr_prompt := s.prompt
	s.is_interactive = cast(bool)posix.isatty(posix.STDIN_FILENO)


	// state.enable_raw(&s)
	// defer state.disable_raw(&s)

	r: reader.ReaderState
	reader.reader_init(&r, &s)
	defer reader.reader_destroy(&r)

	reader.clear_screen()
	execute.setup_signals()
	for s.is_running {
		state.enable_raw(&s)
		input_event := reader.read_line(&r, os.to_stream(os.stdin), curr_prompt)
		state.disable_raw(&s)

		data: string
		#partial switch input_event.type {
		case .Line_Ready:
			data = input_event.data
		case .Read_Error:
			reader.render_error(input_event.err)
			continue
		case .Exit_Shell:
			state.disable_raw(&s)
			return
		case .Interrupt:
			if execute.g_sig.sig_child {
				execute.handle_bg_procs(&s)
			}
			execute.unset_signal()
			continue
		}

		p: parser.Parser
		parser.parser_init(&p, data)

		parse_event := parser.parse(&p)
		switch et in parse_event.parse_event_type {
		case parser.Ast_Ready:
			reader.clear_cmd_buf(&r)
			curr_prompt = s.prompt

			// parser.print_ast(parse_event.command)
			exec := execute.exec(parse_event.command, &s, parse_event.cmd_string)
			if exec.err != .None {
				reader.render_error(exec.msg)
				continue
			}
			s.last_cmd_status = exec.status
			if exec.state == .Background || exec.state == .Suspended {
				message := fmt.tprintf("[%d]- %d\n", len(s.bg_processes) + 1, exec.job.pgid)
				reader.render(message)
				exec.job.id = len(s.bg_processes) + 1
				append(&s.bg_processes, exec.job)
			} else {
				jobs.destroy_job(exec.job)
			}
		case parser.ErrorType:
			if et == .Unclosed_Quote { 	//TODO:add more to this?
				curr_prompt = "dquote> "
			} else {
				reader.render_error(parse_event.parse_err)
				reader.clear_cmd_buf(&r)
				curr_prompt := s.prompt
				continue
			}
		}
		free_all(context.temp_allocator) //free the ast
	}
}
