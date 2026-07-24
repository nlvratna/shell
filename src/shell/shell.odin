package shell

import "../execute"
import "../parser"
import "../reader"
import "../state"
import "core:mem/virtual"
import posix "core:sys/posix"


s: state.ShellState

init_shell :: proc() {
	state.shell_state_init(&s)
}

destroy_shell :: proc() {
	state.shell_state_destroy(&s)
}

run_not_interactive :: proc(data: string) {
	s.is_interactive = false

	context.allocator = virtual.arena_allocator(&s.arena)
	defer free_all(context.allocator)
	defer free_all(context.temp_allocator)

	p: parser.Parser //TODO:the file will have a bang at the start have to include that
	parser.parser_init(&p, data)
	parser_event := parser.parse(&p)
	if parser_event.parse_event_type == .ErrorType {
		reader.render_error(parser_event.parse_err)
	}
	execute.execute(parser_event.program, &s)
}


run_interactive :: proc() {
	s.is_interactive = auto_cast posix.isatty(posix.STDIN_FILENO)


	state.enable_raw(&s)
	defer state.disable_raw(&s)

	r: reader.ReaderState
	reader.reader_init(&r, s.prompt)

	for {
		input_event := reader.read_line(&r)

		data: string
		#partial switch input_event.type {
		case .Line_Ready:
			data = input_event.data
		case .Read_Error:
			reader.render_error(input_event.err)
		}

		context.allocator = virtual.arena_allocator(&s.arena)
		defer free_all(context.allocator)
		defer free_all(context.temp_allocator)

		p: parser.Parser
		parser.parser_init(&p, data)

		parse_event := parser.parse(&p)
		if parse_event.parse_event_type == .ErrorType {
			//ask the user to enter the required token as bash,zsh does
			reader.render_error(parse_event.parse_err)
		}
		execute.execute(parse_event.program, &s)
		reader.clear_buf(&r) //clear the buf before the next line
	}
}

