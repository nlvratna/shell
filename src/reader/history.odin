#+private
package reader

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
// import posix "core:sys/posix"

import "../state"


History :: struct {
	file_path: string,
	entries:   [dynamic]string,
	idx:       int, //point towards the indexed entry
	max_size:  int,
	is_dirty:  bool,
}

history_init :: proc(hist: ^History, s: ^state.ShellState) {
	size := 1000
	if v, ok := s.vars["HISTSIZE"]; ok {
		size, ok = strconv.parse_int(v)
	}
	path := get_file_path(s)
	entries := get_entries(path)

	hist^ = History {
		file_path = path,
		max_size  = size,
		entries   = entries,
		idx       = len(entries) - 1,
	}
}

history_delete :: proc(hist: ^History) {
	if hist.is_dirty {
		//write to file
	}
	delete(hist.file_path)
	for entry in hist.entries {
		delete(entry)
	}
	delete(hist.entries)

	free(hist)
}

hist_get_idx :: proc(hist: ^History) -> string {
	if hist.idx == -1 {
		return ""
	}
	entry := hist.entries[hist.idx]
	hist.idx -= 1
	return entry
}

hist_add_entry :: proc(hist: ^History, entry: string) {
	append(&hist.entries, strings.clone(entry))
	hist.is_dirty = true
	hist.idx += 1
}

get_file_path :: proc(s: ^state.ShellState) -> string {
	if v, ok := s.vars["HISTFILE"]; ok {
		return v
	}

	home := os.get_env("HOME", context.temp_allocator)
	if home != "" {

		path, err := filepath.join({home, ".sh_history"})
		if err == nil {
			return path
		}
	}
	return ""
}

get_entries :: proc(file_path: string) -> (entries: [dynamic]string) {
	entries = make([dynamic]string)

	file, err := os.open(file_path, {.Read})
	if err != nil {
		fmt.eprintf("couldn't open the file:%v\n", err)
		return
	}
	bytes, r_err := os.read_entire_file_from_file(file, context.temp_allocator)
	if r_err != nil {
		fmt.eprintf("couldn't read from the history file:%v\n", err)
		return
	}

	content := string(bytes)
	lines := strings.split_lines(content, context.temp_allocator)

	for line in lines {
		append(&entries, strings.clone(line))
	}

	return
}

