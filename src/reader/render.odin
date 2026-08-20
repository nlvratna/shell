package reader

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"


@(private = "file")
out_stream: io.Stream
err_stream: io.Stream

@(init)
set_stream :: proc "contextless" () {
	context = runtime.default_context()
	out_stream = os.to_stream(os.stdout)
	err_stream = os.to_stream(os.stderr)
}


//TODO: handle print width using current window size and height
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
	io.write(err_stream, transmute([]u8)err)
}

@(private = "file")
handle_render :: proc(data: []byte) {
	io.write(out_stream, data)
}
