package reader

import "core:io"


render :: proc {
	render_string,
	render_bytes,
}


@(private = "file")
render_string :: proc(data: string, stream: io.Stream) {
	io.write_string(stream, data)
}


@(private = "file")
render_bytes :: proc(data: []byte, stream: io.Stream) {
	io.write(stream, data)
}

render_error :: proc(msg: string, stream: io.Stream) {
	render_string(msg, stream)
}

