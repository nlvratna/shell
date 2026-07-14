package reader

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"


@(private = "file")
out_stream: io.Stream

@(init)
set_stream :: proc "contextless" () {
	context = runtime.default_context()
	out_stream := os.to_stream(os.stdout)
}


render :: proc {
	render_string,
	render_bytes,
}


@(private = "file")
render_string :: proc(data: string) {
	handle_render(transmute([]byte)data)
}


@(private = "file")
render_bytes :: proc(data: []byte) {
	handle_render(data)
}

render_error :: proc(msg: string) {
	err := fmt.tprintf("%s %s0m\r\n", msg, CSI)
	handle_render(transmute([]byte)err)
}

@(private = "file")
handle_render :: proc(data: []byte) {
	stream := os.to_stream(os.stdout)
	io.write(stream, data)
}
