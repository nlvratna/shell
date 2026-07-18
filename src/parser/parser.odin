package parser

import "core:strconv"
import "core:strings"

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

	//setup both current token and peek token
	advance_token(p)
	advance_token(p)

}


advance_token :: proc(p: ^Parser) {
	p.curr_token = p.peek_token
	p.peek_token = get_token(&p.t)
}


match_kind :: proc(p: ^Parser, kinds: []TokenKind) -> bool {
	for kind in kinds {
		if p.curr_token.kind == kind {
			advance_token(p)
			return true
		}
	}
	return false
}

match_text :: proc(p: ^Parser, texts: []string) -> bool {
	for text in texts {
		if p.curr_token.text == text {
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
	for p.curr_token.kind == .NEWLINE {
		advance_token(p)
	}
}


parse :: proc(p: ^Parser) -> (Program, Error) {
	cmds := make([dynamic]Command)

	for p.curr_token.kind != .EOF {
		cmd, err := parse_cmdlist(p)
		if err != nil {
			return Program{}, err
		}
		append(&cmds, cmd)
	}

	return Program{cmds = cmds}, nil
}


parse_cmdlist :: proc(p: ^Parser) -> (Command, Error) {
	left, err := parse_and_or(p)
	if err != nil {
		return nil, err
	}

	for p.curr_token.kind == .SEMICOLON {
		operator_kind := p.curr_token.kind

		advance_token(p)

		skip_newlines(p)
		#partial switch p.peek_token.kind {
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

	for p.curr_token.kind == .ORIF || p.curr_token.kind == .ANDIF {
		operator := p.curr_token
		advance_token(p)

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

	if !bang && p.curr_token.kind != .PIPE {
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

	case .LEFTBRACE:
		return parse_bracecmd(p)

	case .FOR:
		return parse_for_cmd(p)

	case .IF:
		return parse_if_cmd(p)
	case .INVALID:
		return nil, .Unexpected_Token
	case:
		return parse_simple_cmd(p)
	}
}

parse_simple_cmd :: proc(p: ^Parser) -> (^SimpleCommand, Error) {
	cmd := new(SimpleCommand)

	cmd.assigns = make([dynamic]string)
	cmd.redirects = make([dynamic]Redirect)
	cmd.words = make([dynamic]string)

	loop: for {
		#partial switch p.curr_token.kind {
		case .WORD:
			word := p.curr_token.text
			if strings.has_prefix(word, "\"") && strings.has_suffix(word, "\"") {
				word = p.curr_token.text[1:len(p.curr_token.text) - 1]
			}
			if strings.has_prefix(word, "'") && strings.has_suffix(word, "'") {
				word = p.curr_token.text[1:len(p.curr_token.text) - 1]
			}
			append(&cmd.words, word)
			advance_token(p)
		case .ASSIGNMENT_WORD:
			append(&cmd.assigns, p.curr_token.text)
			advance_token(p)
		case .LESS, .GREATER, .DGREAT, .IONUMBER:
			fd := -1
			if p.curr_token.kind == .IONUMBER {
				fd, _ = strconv.parse_int(p.curr_token.text)
				advance_token(p)
			}

			if p.curr_token.kind != .LESS &&
			   p.curr_token.kind != .GREATER &&
			   p.curr_token.kind != .DGREAT {
				return nil, .Unexpected_Token
			}

			operator := p.curr_token.kind

			if fd == -1 {
				fd = 0 if operator == .LESS else 1
			}
			advance_token(p)

			if p.curr_token.kind != .WORD {
				return nil, .Unexpected_Token
			}
			redirect := Redirect {
				kind = operator,
				file = p.curr_token.text,
				fd   = fd,
			}

			append(&cmd.redirects, redirect)
			advance_token(p)
		case .AMPERSAND:
			cmd.is_bg = true
			advance_token(p)
		case:
			break loop
		}
	}
	// if len(cmd.words) == 0 && len(cmd.assigns) == 0 && len(cmd.redirects) == 0 {
	// 	return nil, .Unexpected_Token
	// }

	return cmd, nil
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

	if p.curr_token.kind != .WORD {
		return nil, .Unexpected_Token
	}
	for_cmd.variable = p.curr_token.text
	advance_token(p)

	if !match(p, []TokenKind{.IN}) {
		return nil, .Unexpected_Token
	}

	for p.curr_token.kind == .WORD {
		append(&for_cmd.items, p.curr_token.text)
		advance_token(p)
	}

	skip_newlines(p)
	if p.curr_token.kind == .SEMICOLON {
		advance_token(p)
	}
	skip_newlines(p)
	if !match(p, []TokenKind{.DO}) {
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

parse_bracecmd :: proc(p: ^Parser) -> (^BraceGroup, Error) {
	advance_token(p)

	b := new(BraceGroup)

	body, err := parse_cmdlist(p)
	if err != nil {
		return nil, err
	}
	b.body = body

	if !match(p, []TokenKind{.RIGHTBRACE}) {
		return nil, .Unexpected_Token
	}

	return b, nil

}

