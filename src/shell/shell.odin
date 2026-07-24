package shell

import "../execute"
import "../parser"
import "../reader"
import "../state"
import "core:fmt"
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
	program, err := parser.parse(&p)
	if err != nil {
		err_msg := fmt.tprintf("The error:%v", err) //todo:this will be changed
		reader.render_error(err_msg)
	}
	execute.execute(program, &s)
}


run_interactive :: proc() {
	s.is_interactive = auto_cast posix.isatty(posix.STDIN_FILENO)


	state.enable_raw(&s)
	defer state.disable_raw(&s)

	r: reader.ReaderState
	reader.reader_init(&r, s.prompt)

	for {
		execute.reap_bg_processes(&s)

		data := reader.read_line(&r)

		context.allocator = virtual.arena_allocator(&s.arena)
		defer free_all(context.allocator)
		defer free_all(context.temp_allocator)

		p: parser.Parser
		parser.parser_init(&p, data)

		program, err := parser.parse(&p)
		if err != nil {
			err_msg := fmt.tprintf("The error:%v", err) //todo:this will be changed
			reader.render_error(err_msg)
		}
		execute.execute(program, &s)

	}
}

