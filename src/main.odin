package shell

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import posix "core:sys/posix"


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

	s: ShellState
	shell_state_init(&s)
	defer shell_state_destroy(&s)


	if len(os.args) >= 2 {
		file_name := os.args[1]
		s.is_interactive = false

		filepath, err := filepath.abs(file_name)
		if err != nil {
			fmt.eprintln(err)
		}

		byte_data, read_err := os.read_entire_file_from_path(filepath, context.allocator)
		data := string(byte_data[:])
		run(&s, data)
	} else {
		s.is_interactive = auto_cast posix.isatty(posix.STDIN_FILENO)
		enable_raw(&s)
		defer disable_raw(&s)

		run(&s)
	}


}

