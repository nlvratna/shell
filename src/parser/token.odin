package parser


TokenKind :: enum {
	EOF,
	INVALID,


	//basic math ops
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,

	//
	COMMA,
	SEMICOLON,
	QUOTE,
	DOUBLEQUOTE,

	//conditions
	ANDIF,
	ORIF,
	DSEMI,
	DLESS,
	DGREAT,
	LESSAND,
	GREATAND,
	LESSGREAT,
	DLESSDASH,

	//pipe
	CLOBBER,
	PIPE,


	//reserved words
	IF,
	THEN,
	ELSE,
	ELIF,
	FI,
	DO,
	DONE,
	CASE,
	WHEN,
	WHILE,
	UNTIL,
	FOR,
}

