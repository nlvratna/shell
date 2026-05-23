package parser

import "core:testing"

TestCase :: struct {
	name:     string,
	input:    string,
	expected: []Token,
}

@(test)
test_lexer :: proc(t: ^testing.T) {

	tests := []TestCase {
		{
			name = "Basic Command and Arguments",
			input = "ls -la /var/log",
			expected = []Token {
				{text = "ls", kind = .WORD},
				{text = "-la", kind = .WORD},
				{text = "/var/log", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Reserved Keywords vs Words",
			input = "if while my_while",
			expected = []Token {
				{text = "if", kind = .IF},
				{text = "while", kind = .WHILE},
				{text = "my_while", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Multi-Character Operators",
			input = "> >> < <<- | || && ; ;;",
			expected = []Token {
				{text = ">", kind = .GREATER},
				{text = ">>", kind = .DGREAT},
				{text = "<", kind = .LESS},
				{text = "<<-", kind = .DLESSDASH},
				{text = "|", kind = .PIPE},
				{text = "||", kind = .ORIF},
				{text = "&&", kind = .ANDIF},
				{text = ";", kind = .SEMICOLON},
				{text = ";;", kind = .DSEMI},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Quotes suppress operators and spaces",
			input = "echo \"hello | world\" 'single && quote'",
			expected = []Token {
				{text = "echo", kind = .WORD},
				{text = "\"hello | world\"", kind = .WORD},
				{text = "'single && quote'", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Real-world pipeline",
			input = "cat file.txt | grep \"error\" > out.log &",
			expected = []Token {
				{text = "cat", kind = .WORD},
				{text = "file.txt", kind = .WORD},
				{text = "|", kind = .PIPE},
				{text = "grep", kind = .WORD},
				{text = "\"error\"", kind = .WORD},
				{text = ">", kind = .GREATER},
				{text = "out.log", kind = .WORD},
				{text = "&", kind = .AMPERSAND},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Unclosed Double Quote (Error Handling)",
			input = "echo \"unclosed string",
			expected = []Token {
				{text = "echo", kind = .WORD},
				{text = "Unclosed double quote", kind = .INVALID},
			},
		},
		{
			name = "IO Numbers and File Descriptors",
			input = "2> error.log 1>&2",
			expected = []Token {
				{text = "2", kind = .IONUMBER},
				{text = ">", kind = .GREATER},
				{text = "error.log", kind = .WORD},
				{text = "1", kind = .IONUMBER},
				{text = ">&", kind = .GREATAND},
				{text = "2", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Words Starting with Numbers (No Fragmenting)",
			input = "1st_place 123abc",
			expected = []Token {
				{text = "1st_place", kind = .WORD},
				{text = "123abc", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Assignment Words",
			input = "FOO=bar PATH=/bin/bash 123BAD=foo",
			expected = []Token {
				{text = "FOO=bar", kind = .ASSIGNMENT_WORD},
				{text = "PATH=/bin/bash", kind = .ASSIGNMENT_WORD},
				{text = "123BAD=foo", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Mid-Word Quoting (The Ultimate Test)",
			input = "echo 123\"hello world\"456",
			expected = []Token {
				{text = "echo", kind = .WORD},
				{text = "123\"hello world\"456", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
		{
			name = "Test",
			input = "echo hello\'world\'",
			expected = []Token {
				{text = "echo", kind = .WORD},
				{text = "hello\'world\'", kind = .WORD},
			},
		},
		{
			name = "Standalone EQUAL Token (Custom Syntax)",
			input = "FOO = bar test 1 = 1",
			expected = []Token {
				{text = "FOO", kind = .WORD},
				{text = "=", kind = .EQUAL},
				{text = "bar", kind = .WORD},
				{text = "test", kind = .WORD},
				{text = "1", kind = .WORD},
				{text = "=", kind = .EQUAL},
				{text = "1", kind = .WORD},
				{text = "EOF", kind = .EOF},
			},
		},
	}

	for tc in tests {
		tokenizer: Tokenizer
		tokenizer_init(&tokenizer, tc.input)

		for expected_tok, i in tc.expected {
			got_tok := get_token(&tokenizer)
			testing.expectf(
				t,
				got_tok.kind == expected_tok.kind,
				"[%s] Token %d mismatch: Expected Kind %v, Got %v (text: '%s')",
				tc.name,
				i,
				expected_tok.kind,
				got_tok.kind,
				got_tok.text,
			)

			testing.expectf(
				t,
				got_tok.text == expected_tok.text,
				"[%s] Token %d mismatch: Expected text '%s', Got '%s'",
				tc.name,
				i,
				expected_tok.text,
				got_tok.text,
			)

			if got_tok.kind == .INVALID {
				break
			}
		}
	}
}

