package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "shell"


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

	shell.init_shell()
	defer shell.destroy_shell()


	if len(os.args) >= 2 {
		file_name := os.args[1]

		filepath, err := filepath.abs(file_name)
		if err != nil {
			fmt.eprintln(err)
		}
		byte_data, read_err := os.read_entire_file_from_path(filepath, context.allocator)
		defer delete(byte_data)

		data := string(byte_data[:])

		shell.run_not_interactive(data)
	} else {
		shell.run_interactive()
	}

}

