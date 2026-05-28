package parser


Parser :: struct {
	t:          Tokenizer,
	curr_token: Token,
	peek_token: Token,
}

Error :: enum {
	None,
	Unexpected_Token,
	Unclosed_Quote,
}


parser_init :: proc(p: ^Parser, data: string) {
	t: Tokenizer
	tokenizer_init(&t, data)

	p^ = Parser {
		t = t,
	}

	advance_token(p)
	advance_token(p)

}


advance_token :: proc(p: ^Parser) {
	p.curr_token = p.peek_token
	p.peek_token = get_token(&p.t)

}


match_kind :: proc(p: ^Parser, kinds: []TokenKind) -> bool {
	for kind in kinds {
		if p.peek_token.kind == kind {
			advance_token(p)
			return true
		}
	}
	return false
}

match_text :: proc(p: ^Parser, texts: []string) -> bool {
	for text in texts {
		if p.peek_token.text == text {
			advance_token(p)
			return true
		}
	}
	return false
}

match :: proc {
	match_text,
	match_kind,
}

skip_newlines :: proc(p: ^Parser) {
	for p.peek_token.kind == .NEWLINE {
		advance_token(p)
	}
}


parse :: proc(p: ^Parser) -> (^Program, Error) {
	prog := new(Program)
	cmds := make([dynamic]Command)

	for p.curr_token.kind != .EOF {
		cmd, err := parse_cmdlist(p)
		if err != nil {
			return nil, err
		}
		append(&cmds, cmd)
	}

	prog.cmds = cmds
	return prog, nil
}


parse_cmdlist :: proc(p: ^Parser) -> (Command, Error) {
	left, err := parse_and_or(p)
	if err != nil {
		return nil, err
	}

	if p.curr_token.kind == .SEMICOLON {
		operator_kind := p.curr_token.kind
		advance_token(p)

		skip_newlines(p)

		#partial switch p.curr_token.kind {
		case .EOF, .RIGHTPAREN, .RIGHTBRACE, .FI, .THEN, .DONE, .ELIF, .ELSE:
			return left, nil
		}

		right, err := parse_and_or(p)
		if err != nil {
			return left, err
		}

		cmdlist := new(CommandList)
		cmdlist.left = left
		cmdlist.operator = operator_kind
		cmdlist.right = right

		left = cmdlist
	}

	return left, nil
}

parse_and_or :: proc(p: ^Parser) -> (Command, Error) {
	left, err := parse_pipeline(p)
	if err != nil {
		return nil, err
	}

	for match(p, []TokenKind{.ORIF, .ANDIF}) {
		operator := p.curr_token

		right, err := parse_pipeline(p)
		if err != nil {
			return left, err
		}

		cmdlist := new(CommandList)
		cmdlist.left = left
		cmdlist.operator = operator.kind
		cmdlist.right = right

		left = cmdlist

	}

	return left, nil
}

parse_pipeline :: proc(p: ^Parser) -> (Command, Error) {

	bang: bool

	if p.curr_token.kind == .BANG {
		bang = true
		advance_token(p)
	}

	cmd, err := parse_cmd(p)
	if err != nil {
		return nil, err
	}

	if !bang && p.peek_token.kind == .PIPE {
		return cmd, nil
	}

	pipeline := new(Pipeline)
	pipeline.bang = bang

	append(&pipeline.commands, cmd)


	for match(p, []TokenKind{.PIPE}) {
		cmd, err = parse_cmd(p)
		if err != nil {
			return pipeline, err
		}
		append(&pipeline.commands, cmd)
	}

	return pipeline, nil

}


parse_cmd :: proc(p: ^Parser) -> (Command, Error) {
	#partial switch p.curr_token.kind {

	case .LEFTPAREN:
		return parse_subshell_cmd(p)

	case .FOR:
		return parse_for_cmd(p)

	case .IF:
		return parse_if_cmd(p)
	case:
		return parse_simple_cmd(p)
	}
}

parse_simple_cmd :: proc(p: ^Parser) -> (^SimpleCommand, Error) {
	//TODO
	return nil, nil
}

parse_subshell_cmd :: proc(p: ^Parser) -> (^Subshell, Error) {
	advance_token(p)

	subshell := new(Subshell)
	cmd, err := parse_cmdlist(p)
	if err != nil {
		return nil, err
	}
	if !match(p, []TokenKind{.RIGHTPAREN}) {
		return nil, .Unexpected_Token
	}

	subshell.body = cmd
	return subshell, nil
}

parse_for_cmd :: proc(p: ^Parser) -> (^ForLoop, Error) {
	advance_token(p)

	for_cmd := new(ForLoop)
	if !match(p, []TokenKind{.WORD}) {
		return nil, .Unexpected_Token
	}
	for_cmd.variable = p.curr_token.text

	if !match(p, []TokenKind{.IN}) {
		return nil, .Unexpected_Token
	}

	for match(p, []TokenKind{.WORD}) {
		append(&for_cmd.items, p.curr_token.text)
	}
	skip_newlines(p)
	if !match(p, []TokenKind{.SEMICOLON, .DO}) {
		return nil, .Unexpected_Token
	}
	skip_newlines(p)

	body, err := parse_cmdlist(p)
	if err != nil {
		return nil, err
	}
	for_cmd.body = body

	if !match(p, []TokenKind{.DONE}) {
		return nil, .Unexpected_Token
	}

	return for_cmd, nil
}

parse_if_cmd :: proc(p: ^Parser) -> (^IfClause, Error) {
	parse_if :: proc(p: ^Parser, if_cmd: ^IfClause) -> Error {

		condition := parse_cmdlist(p) or_return
		if_cmd.condition = condition

		if match(p, []TokenKind{.SEMICOLON}) {
		}

		skip_newlines(p)

		if !match(p, []TokenKind{.THEN}) {
			return .Unexpected_Token
		}

		then_branch := parse_cmdlist(p) or_return

		if_cmd.then_branch = then_branch

		return nil
	}


	advance_token(p)

	if_clause := new(IfClause)

	if err := parse_if(p, if_clause); err != nil {
		return nil, err
	}

	curr_if := if_clause

	for match(p, []TokenKind{.ELIF}) {
		elif_clause := new(IfClause)

		if err := parse_if(p, elif_clause); err != nil {
			return nil, err
		}
		curr_if.else_branch = elif_clause

		curr_if = elif_clause
	}

	if match(p, []TokenKind{.ELSE}) {
		skip_newlines(p)

		else_body, err := parse_cmdlist(p)
		if err != nil {
			return nil, err
		}

		curr_if.else_branch = else_body
	}

	if !match(p, []TokenKind{.FI}) {
		return nil, .Unexpected_Token
	}

	return if_clause, nil
}

