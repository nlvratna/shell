package parser

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Tokenizer :: struct {
	data:   string,
	offset: int,
	ch:     rune,
	w:      int,
}

tokenizer_init :: proc(t: ^Tokenizer, data: string) {

	t^ = Tokenizer {
		offset = 0,
		data   = data,
	}

	next_rune(t)

	if t.ch == utf8.RUNE_EOF {
		next_rune(t)
	}
}

next_rune :: proc(t: ^Tokenizer) -> rune {
	if t.offset < len(t.data) {
		t.offset += t.w
		t.ch, t.w = utf8.decode_rune_in_string(t.data[t.offset:])
		//
	}

	if t.offset >= len(t.data) {

		t.ch = utf8.RUNE_EOF
		t.w = 1
	}
	return t.ch
}


get_token :: proc(t: ^Tokenizer) -> Token {
	match :: proc(t: ^Tokenizer, expected: rune) -> bool {
		if t.ch == expected {
			next_rune(t)
			return true
		}
		return false
	}

	consume_quote :: proc(t: ^Tokenizer, quote: rune) -> bool {
		for t.ch != utf8.RUNE_EOF && t.ch != quote {
			next_rune(t)
		}

		if t.ch == utf8.RUNE_EOF {
			return false
		}

		next_rune(t)
		return true
	}

	is_all_digits :: proc(s: string) -> bool {
		if len(s) == 0 {return false}
		for r in s {
			if !unicode.is_digit(r) do return false
		}
		return true
	}

	is_identifier :: proc(text: string) -> bool {
		if len(text) == 0 {
			return false
		}
		for i in 0 ..< len(text) {
			c := rune(text[i])
			if i == 0 {
				if !unicode.is_alpha(c) {
					return false
				}
			} else {
				if !unicode.is_alpha(c) && !unicode.is_digit(c) && c != '_' {
					return false
				}
			}
		}
		return true
	}

	is_assignment_word :: proc(text: string) -> bool {
		id := strings.index_rune(text, '=')
		if id <= 0 do return false

		for i in 0 ..< id {
			c := rune(text[i])
			if i == 0 {
				if !unicode.is_alpha(c) && c != '_' do return false
			} else {
				if !unicode.is_alpha(c) && !unicode.is_digit(c) && c != '_' do return false
			}
		}
		return true
	}


	for t.ch == ' ' || t.ch == '\t' || t.ch == '\r' {
		next_rune(t)
	}

	// if t.ch == utf8.RUNE_EOF {
	// 	return new_token("EOF", .EOF)
	//    }


	start_pos := t.offset
	ch := t.ch

	next_rune(t)

	kind: TokenKind

	switch ch {
	case '\n':
		kind = .NEWLINE
	case '(':
		kind = .LEFTPAREN
	case ')':
		kind = .RIGHTPAREN
	case '{':
		kind = .LEFTBRACE
	case '}':
		kind = .RIGHTBRACE
	case '!':
		kind = .BANG
	case '=':
		kind = .EQUAL
	case ';':
		if t.ch == ';' {
			kind = .DSEMI
			next_rune(t)
		} else {
			kind = .SEMICOLON
		}
	case '&':
		kind = match(t, '&') ? .ANDIF : .AMPERSAND
	case '|':
		kind = match(t, '|') ? .ORIF : .PIPE
	case '>':
		if match(t, '|') {
			kind = .CLOBBER
		} else if match(t, '>') {
			kind = .DGREAT
		} else if match(t, '&') {
			kind = .GREATAND
		} else {
			kind = .GREATER
		}
	case '<':
		if match(t, '<') {
			kind = match(t, '-') ? .DLESSDASH : .DLESS
		} else if match(t, '&') {
			kind = .LESSAND
		} else if match(t, '>') {
			kind = .LESSGREAT
		} else {
			kind = .LESS
		}
	case utf8.RUNE_EOF, '\x00':
		kind = .EOF
	case:
		//everything else is a string in a shell
		if ch == '\'' {
			if !consume_quote(t, '\'') {
				return new_token("Unclosed single quote", .INVALID)
			}
		} else if ch == '"' {
			if !consume_quote(t, '"') {
				return new_token("Unclosed double quote", .INVALID)
			}
		}

		for t.ch != utf8.RUNE_EOF {
			if t.ch == ' ' || t.ch == '\t' || t.ch == '\n' || is_shell_operator(t.ch) {

				break
			}

			if t.ch == '\'' {
				next_rune(t)
				if !consume_quote(t, '\'') {
					return new_token("Unclosed single quote", .INVALID)
				}
			} else if t.ch == '"' {
				next_rune(t)
				if !consume_quote(t, '"') {
					return new_token("Unclosed double quote", .INVALID)
				}
			} else {
				next_rune(t)
			}
		}

		text := t.data[start_pos:t.offset]


		if is_all_digits(text) {
			if t.ch == '<' || t.ch == '>' {
				kind = .IONUMBER
			} else {
				kind = .WORD //number
			}
		} else {
			kind = look_up(text)
			if kind == .WORD && is_assignment_word(text) {
				kind = .ASSIGNMENT_WORD
			}
		}
	}

	text := t.data[start_pos:t.offset]

	return new_token(text, kind)
}

@(private = "file")
is_shell_operator :: proc(c: rune) -> bool {
	switch c {
	case '|', '&', ';', '<', '>':
		return true
	case:
		return false
	}
}

