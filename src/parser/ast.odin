package parser

Program :: struct {
	cmds: [dynamic]Command,
}

Command :: union {
	^SimpleCommand,
	^Pipeline,
	^CommandList,
	^Subshell,
	^BraceGroup,
	^ForLoop,
	^WhileLoop,
	^UntilLoop,
	^IfClause,
	^CaseClause,
	^FuncDef,
}

Redirect :: struct {
	kind: TokenKind,
	file: string,
	fd:   int,
}

SimpleCommand :: struct {
	assigns:   [dynamic]string,
	words:     [dynamic]string,
	redirects: [dynamic]Redirect,
}

Pipeline :: struct {
	bang:     bool,
	commands: [dynamic]^Command,
}

CommandList :: struct {
	left:     ^Command,
	operator: TokenKind,
	right:    ^Command,
}

Subshell :: struct {
	body: ^Command,
}

BraceGroup :: struct {
	body: ^Command,
}

ForLoop :: struct {
	variable: string,
	items:    [dynamic]string,
	body:     ^Command,
}

WhileLoop :: struct {
	condition: ^Command,
	body:      ^Command,
}

UntilLoop :: struct {
	condition: ^Command,
	body:      ^Command,
}

IfClause :: struct {
	condition:   ^Command,
	then_branch: ^Command,
	else_branch: Maybe(^Command),
}

CaseItem :: struct {
	patterns: [dynamic]string,
	body:     ^Command,
}

CaseClause :: struct {
	word:  string,
	items: [dynamic]^CaseItem,
}


FuncDef :: struct {
	name:      string,
	body:      ^Command,
	redirects: [dynamic]^Redirect,
}

