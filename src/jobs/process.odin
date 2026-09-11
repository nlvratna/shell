package jobs

import "../parser"
import "core:os"
import "core:path/filepath"
import "core:strings"
import posix "core:sys/posix"
import "core:unicode"

ProcessErrorType :: enum {
	None,
	FileOpen_Error,
	Redirect_Error,
}

ArgType :: enum {
	Text,
	Command,
}

Arg :: struct {
	type: ArgType,
	val:  string,
}

Process :: struct {
	pid:           posix.pid_t,
	id:            int,
	env:           map[cstring]cstring,
	cmd:           cstring,
	args:          [dynamic]string,
	expanded_args: [dynamic]cstring,
	redirects:     [dynamic]parser.Redirect,
	in_fd:         posix.FD,
	out_fd:        posix.FD,
	is_first:      bool,
	is_last:       bool,
	exit_status:   int,
}

init_process :: proc(p: ^Process, j: ^Job) {
	p.in_fd = j.stdin
	p.out_fd = j.stdout
}

destroy_process :: proc(p: ^Process) {
	for k, v in p.env {
		delete(k); delete(v)
	}
	delete(p.env)
	for arg in p.args {delete(arg)}
	delete(p.args)
	for e in p.expanded_args {if e != nil do delete(e)}
	delete(p.expanded_args)
	for r in p.redirects {delete(r.file)}
	delete(p.redirects)
	free(p)
}

// Updated to accept the final resolved arguments from the execute package
populate_process :: proc(
	vars: map[string]string,
	p: ^Process,
	cmd: ^parser.SimpleCommand,
	final_args: [dynamic]string,
) -> ProcessErrorType {
	append(&p.redirects, ..cmd.redirects[:])

	p.env = make(map[cstring]cstring)
	for assign in cmd.assigns {
		idx := strings.index_byte(assign, '=')
		if idx == -1 do continue
		key := strings.clone_to_cstring(assign[:idx])
		val := strings.clone_to_cstring(assign[idx + 1:])
		p.env[key] = val
	}

	p.args = make([dynamic]string, 0, len(cmd.words))
	for w in cmd.words do append(&p.args, strings.clone(w))

	p.expanded_args = make([dynamic]cstring, 0, len(final_args) + 1)
	for arg in final_args {
		append(&p.expanded_args, strings.clone_to_cstring(arg))
	}
	append(&p.expanded_args, nil) // Null terminate for execvp

	if len(p.expanded_args) > 1 {
		p.cmd = p.expanded_args[0]
	}
	return .None
}

parse_word_into_args :: proc(word: string, env: map[string]string) -> [dynamic]Arg {
	args := make([dynamic]Arg)

	// 1. Tilde Expansion first
	t_word := word
	if word == "~" {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" do t_word = home
	} else if strings.has_prefix(word, "~/") {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" do t_word = strings.concatenate({home, word[1:]}, context.temp_allocator)
	}

	builder := strings.builder_make()
	in_single := false

	i := 0
	for i < len(t_word) {
		char := t_word[i]

		if char == '\'' {
			in_single = !in_single
			strings.write_byte(&builder, char)
			i += 1
			continue
		}

		if char == '$' && !in_single {
			// Check for $(command)
			if i + 1 < len(t_word) && t_word[i + 1] == '(' {
				// Flush current text chunk
				if strings.builder_len(builder) > 0 {
					append(
						&args,
						Arg{type = .Text, val = strings.clone(strings.to_string(builder))},
					)
					strings.builder_reset(&builder)
				}

				i += 2 // skip "$("
				start := i
				paren_count := 1
				for i < len(t_word) && paren_count > 0 {
					if t_word[i] == '(' do paren_count += 1
					if t_word[i] == ')' do paren_count -= 1
					i += 1
				}

				end_idx := paren_count == 0 ? i - 1 : i
				cmd_str := t_word[start:end_idx]

				append(&args, Arg{type = .Command, val = strings.clone(cmd_str)})
				continue
			}

			// Handle ${VAR}
			if i + 1 < len(t_word) && t_word[i + 1] == '{' {
				i += 2
				start := i
				for i < len(t_word) && t_word[i] != '}' do i += 1
				var_name := t_word[start:i]
				if i < len(t_word) && t_word[i] == '}' do i += 1
				if val, ok := env[var_name]; ok do strings.write_string(&builder, val)
				continue
			}

			// Handle $VAR
			i += 1
			if i < len(t_word) {
				start := i
				r := rune(t_word[i])
				if unicode.is_alpha(r) || r == '_' {
					for i < len(t_word) && (unicode.is_alpha(rune(t_word[i])) || unicode.is_digit(rune(t_word[i])) || t_word[i] == '_') do i += 1
					var_name := t_word[start:i]
					if val, ok := env[var_name]; ok do strings.write_string(&builder, val)
				} else if r == '?' || r == '$' || unicode.is_digit(r) {
					var_name := t_word[start:start + 1]
					i += 1
					if val, ok := env[var_name]; ok do strings.write_string(&builder, val)
				} else {
					strings.write_byte(&builder, '$')
				}
			} else {
				strings.write_byte(&builder, '$')
			}
		} else {
			strings.write_byte(&builder, char)
			i += 1
		}
	}

	// Flush remaining text
	if strings.builder_len(builder) > 0 {
		append(&args, Arg{type = .Text, val = strings.clone(strings.to_string(builder))})
	}
	strings.builder_destroy(&builder)

	return args
}

expand_glob :: proc(word: string) -> [dynamic]string {
	results := make([dynamic]string)

	matches, err := filepath.glob(word)

	if err == nil && len(matches) > 0 {
		for match in matches {
			append(&results, strings.clone(match))
		}
		for match in matches {
			delete(match)
		}
		delete(matches)
	} else {
		append(&results, strings.clone(word))
	}

	return results
}

remove_quotes :: proc(word: string) -> string {
	builder := strings.builder_make()
	in_single, in_double, escaped := false, false, false
	for i := 0; i < len(word); i += 1 {
		char := word[i]
		if escaped {strings.write_byte(&builder, char); escaped = false; continue}
		if char == '\\' && !in_single {escaped = true; continue}
		if char == '\'' && !in_double {in_single = !in_single; continue}
		if char == '"' && !in_single {in_double = !in_double; continue}
		strings.write_byte(&builder, char)
	}
	return strings.to_string(builder)
}
