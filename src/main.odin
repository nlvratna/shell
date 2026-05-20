package shell

import "core:bufio"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import posix "core:sys/posix"
import "reader"


main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
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
		free_all(context.temp_allocator)
	}
}

