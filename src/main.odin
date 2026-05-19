package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import posix "core:sys/posix"
import "reader"


main :: proc() {

	if len(os.args) >= 2 {
		file_name := os.args[1]

		filepath, err := filepath.abs(file_name)
		if err != nil {
			fmt.eprintln(err)
		}

		file, error := os.open(filepath, {.Read})
		if error != nil {
			fmt.eprintln(err) //can do better?
		}
		defer os.close(file)
		handle_file(file)
	}

	if !posix.isatty(posix.STDIN_FILENO) {
		handle_file(os.stdin)
	}

	reader.enable_raw_mode()
	defer reader.disable_raw_mode()

	exec()


	free_all(context.temp_allocator)
}

handle_file :: proc(file: ^os.File) {
	scanner: bufio.Scanner
	bufio.scanner_init(&scanner, os.to_stream(file))
	defer bufio.scanner_destroy(&scanner)
	defer free(&scanner)

	// for bufio.scanner_scan(scanner) {
	// 	// line := bufio.scanner_text(scanner)
	// }


}

exec :: proc() {
	r := reader.reader_ini("$ ")
	defer reader.reader_fini(r)
	for {
		reader.read_line(r)
	}
}

