package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "reader"


main :: proc() {

	r := reader.reader_ini("$ ")
	defer reader.reader_fini(r)

	file := os.stdin
	defer os.close(file)

	if len(os.args) >= 2 {
		file_name := os.args[1]

		filepath, err := filepath.abs(file_name)
		if err != nil {
			fmt.eprintln(err)
		}

		file, error := os.open(filepath, {.Read})
		if error != nil {
			fmt.eprintln(err)
		}
	}

	for {
		reader.read_line(r, file)
	}

	free_all(context.temp_allocator)
}

