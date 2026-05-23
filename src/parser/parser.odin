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

	// ls -la || ls -lH
	advance_token(p)
	advance_token(p)

}


advance_token :: proc(p: ^Parser) {
	p.curr_token = p.peek_token
	p.peek_token = get_token(&p.t)

}


match :: proc(p: ^Parser, kinds: []TokenKind) -> bool {
	for kind in kinds {
		if p.peek_token.kind == kind {
			advance_token(p)
			return true
		}
	}
	return false
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
	left, err := parse_pipeline(p)
	if err != nil {
		return nil, err
	}
	for match(p, {.ORIF, .ANDIF}) {
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
	return nil, nil
}

