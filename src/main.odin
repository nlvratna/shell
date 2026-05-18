package main

import "core:os"

import "reader"


main :: proc() {

	r: reader.ReaderState
	reader.reader_ini(&r, "$  ")
	defer reader.reader_fini(&r)

	if len(os.args) >= 2 {
	} else {
		stream := os.to_stream(os.stdin)
		defer os.close(os.stdin)
		reader.read_line(&r, stream)
	}


}

