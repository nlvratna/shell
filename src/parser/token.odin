package parser

TokenKind :: enum {
	EOF,
	INVALID,
	WORD,
	ASSIGNMENT_WORD,
	IONUMBER,


	//
	NEWLINE,
	SEMICOLON,
	DSEMI,
	AMPERSAND,
	PIPE,
	ANDIF,
	ORIF,

	// Redirections
	LESS,
	GREATER,
	DLESS,
	DGREAT,
	LESSAND,
	GREATAND,
	LESSGREAT,
	DLESSDASH,
	CLOBBER,

	// Reserved Words
	IF,
	THEN,
	ELIF,
	ELSE,
	FI,
	DO,
	DONE,
	CASE,
	ESAC,
	WHILE,
	UNTIL,
	FOR,
	IN,

	// Symbols
	LEFTPAREN,
	RIGHTPAREN,
	LEFTBRACE,
	RIGHTBRACE,
	BANG,
}

Token :: struct {
	text: string,
	kind: TokenKind,
}

look_up :: proc(text: string) -> TokenKind {
	switch text {
	case "if":
		return .IF
	case "then":
		return .THEN
	case "elif":
		return .ELIF
	case "else":
		return .ELSE
	case "fi":
		return .FI
	case "do":
		return .DO
	case "done":
		return .DONE
	case "case":
		return .CASE
	case "esac":
		return .ESAC
	case "while":
		return .WHILE
	case "until":
		return .UNTIL
	case "for":
		return .FOR
	case "in":
		return .IN
	}

	return .WORD
}

new_token :: proc(text: string, kind: TokenKind) -> Token {
	return Token{text = text, kind = kind}
}

