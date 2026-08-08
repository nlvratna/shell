package parser


import "core:fmt"


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
	is_bg:     bool,
}

Pipeline :: struct {
	bang:     bool,
	commands: [dynamic]Command,
}

CommandList :: struct {
	left:     Command,
	operator: TokenKind,
	right:    Command,
}

Subshell :: struct {
	body: Command,
}

BraceGroup :: struct {
	body: Command,
}

ForLoop :: struct {
	variable: string,
	items:    [dynamic]string,
	body:     Command,
}

WhileLoop :: struct {
	condition: Command,
	body:      Command,
}

UntilLoop :: struct {
	condition: Command,
	body:      Command,
}

IfClause :: struct {
	condition:   Command,
	then_branch: Command,
	else_branch: Command,
}

CaseItem :: struct {
	patterns: [dynamic]string,
	body:     Command,
}

CaseClause :: struct {
	word:  string,
	items: [dynamic]CaseItem,
}


FuncDef :: struct {
	name:      string,
	body:      Command,
	redirects: [dynamic]Redirect,
}


print_indent :: proc(level: int) {
	for _ in 0 ..< level {
		fmt.print("  ")
	}
}

print_ast :: proc(cmd: Command) {
	fmt.println("=== ABSTRACT SYNTAX TREE ===")
	print_command(cmd, 0)
	fmt.println("----------------------------")
}

print_command :: proc(cmd: Command, level: int) {
	if cmd == nil {
		return
	}

	print_indent(level)

	#partial switch c in cmd {
	case ^SimpleCommand:
		fmt.printf(
			"SimpleCommand: words=%v, assigns=%v, redirects=%v\n",
			c.words,
			c.assigns,
			c.redirects,
		)

	case ^Pipeline:
		fmt.printf("Pipeline (bang=%v):\n", c.bang)
		for pipe_cmd in c.commands {
			print_command(pipe_cmd, level + 1)
		}

	case ^CommandList:
		fmt.printf("CommandList (operator: %v)\n", c.operator)
		print_indent(level + 1)
		fmt.println("Left:")
		print_command(c.left, level + 2)
		print_indent(level + 1)
		fmt.println("Right:")
		print_command(c.right, level + 2)

	case ^IfClause:
		fmt.println("IfClause:")
		print_indent(level + 1)
		fmt.println("Condition:")
		print_command(c.condition, level + 2)
		print_indent(level + 1)
		fmt.println("Then:")
		print_command(c.then_branch, level + 2)
		if c.else_branch != nil {
			print_indent(level + 1)
			fmt.println("Else/Elif:")
			print_command(c.else_branch, level + 2)
		}

	case ^ForLoop:
		fmt.printf("ForLoop (var=%s, items=%v):\n", c.variable, c.items)
		print_command(c.body, level + 1)
	case ^WhileLoop:
		fmt.println("While Loop:")
		print_command(c.condition, level + 2)
		print_command(c.body, level + 2)
	case ^Subshell:
		fmt.println("Subshell:")
		print_command(c.body, level + 1)

	case ^BraceGroup:
		fmt.println("BraceGroup:")
		print_command(c.body, level + 1)
	}
}

