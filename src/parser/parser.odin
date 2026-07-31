package parser//for a command

import "core:fmt"
import "core:strconv"
import "core:strings"

Parser :: struct {
	t:          Tokenizer,
	curr_token: Token,
	peek_token: Token,
}

ErrorType :: enum {
	None,
	Unexpected_Token,
	Unclosed_Quote,
}

ParseError :: struct {
	err_type: ErrorType,
	msg:      string,
}

ParseEventType :: enum {
	Ast_Ready,
	ErrorType,
}


ParserEvent :: struct {
	parse_event_type: ParseEventType,
	// program:          Program, // is this the better option?
	command:          Command, //should I take this to handle errors in execution
	parse_err:        string,
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


//TODO : remove some code duplication
parse :: proc(p: ^Parser) -> ParserEvent {

	skip_newlines(p)
	if p.curr_token.kind == .EOF {
	}
	context.allocator = context.temp_allocator //is this good?
	cmd, err := parse_cmdlist(p)
	if err.err_type != .None {
		return ParserEvent{parse_err = err.msg, parse_event_type = .ErrorType}
	}
	skip_newlines(p)

	return ParserEvent{parse_event_type = .Ast_Ready, command = cmd}
}


parse_cmdlist :: proc(p: ^Parser) -> (Command, ParseError) {
	left, err := parse_and_or(p)
	if err.err_type != .None {
		return nil, err
	}

	for p.curr_token.kind == .SEMICOLON {
		operator_kind := p.curr_token.kind

		advance_token(p)

		skip_newlines(p)
		#partial switch p.peek_token.kind {
		case .EOF, .RIGHTPAREN, .RIGHTBRACE, .FI, .THEN, .DONE, .ELIF, .ELSE:
			return left, ParseError{err_type = .None}
		}

		right, err := parse_and_or(p)
		if err.err_type != .None {
			return left, err
		}

		cmdlist := new(CommandList)
		cmdlist.left = left
		cmdlist.operator = operator_kind
		cmdlist.right = right
		left = cmdlist
	}

	return left, ParseError{err_type = .None}
}

parse_and_or :: proc(p: ^Parser) -> (Command, ParseError) {
	left, err := parse_pipeline(p)
	if err.err_type != .None {
		return nil, err
	}

	for p.curr_token.kind == .ORIF || p.curr_token.kind == .ANDIF {
		operator := p.curr_token
		advance_token(p)

		right, err := parse_pipeline(p)
		if err.err_type != .None {
			return nil, err
		}

		cmdlist := new(CommandList)
		cmdlist.left = left
		cmdlist.operator = operator.kind
		cmdlist.right = right
		left = cmdlist
	}
	return left, ParseError{err_type = .None}
}

parse_pipeline :: proc(p: ^Parser) -> (Command, ParseError) {

	bang: bool
	if p.curr_token.kind == .BANG {
		bang = true
		advance_token(p)
	}

	cmd, err := parse_cmd(p)
	if err.err_type != .None {
		return nil, err
	}

	if !bang && p.curr_token.kind != .PIPE {
		return cmd, ParseError{err_type = .None}
	}

	pipeline := new(Pipeline)
	pipeline.bang = bang

	append(&pipeline.commands, cmd)


	for match(p, []TokenKind{.PIPE}) {
		cmd, err = parse_cmd(p)
		if err.err_type != .None {
			return pipeline, err
		}
		append(&pipeline.commands, cmd)
	}

	return pipeline, ParseError{err_type = .None}

}


parse_cmd :: proc(p: ^Parser) -> (Command, ParseError) {
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
		msg := fmt.tprintf("Unexptected token,%s", p.curr_token.text)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
	case:
		return parse_simple_cmd(p)
	}
}

parse_simple_cmd :: proc(p: ^Parser) -> (^SimpleCommand, ParseError) {
	cmd := new(SimpleCommand)

	cmd.assigns = make([dynamic]string)
	cmd.redirects = make([dynamic]Redirect)
	cmd.words = make([dynamic]string)

	loop: for {
		#partial switch p.curr_token.kind {
		case .WORD:
			word := p.curr_token.text
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
				msg := fmt.tprintf("Unexptected token,%s", p.curr_token.text)
				return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
			}

			operator := p.curr_token.kind

			if fd == -1 {
				fd = 0 if operator == .LESS else 1
			}
			advance_token(p)

			if p.curr_token.kind != .WORD {
				msg := fmt.tprintf("Unexptected token,%s", p.curr_token.text)
				return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
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

	return cmd, ParseError{err_type = .None}
}

parse_subshell_cmd :: proc(p: ^Parser) -> (^Subshell, ParseError) {
	advance_token(p)

	subshell := new(Subshell)
	cmd, err := parse_cmdlist(p)
	if err.err_type != .None {
		return nil, err
	}
	if !match(p, []TokenKind{.RIGHTPAREN}) {
		msg := fmt.tprintf("Unexptected token,%s", p.curr_token.text, true)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
	}

	subshell.body = cmd
	return subshell, ParseError{err_type = .None}
}

parse_for_cmd :: proc(p: ^Parser) -> (^ForLoop, ParseError) {
	advance_token(p)

	for_cmd := new(ForLoop)

	if p.curr_token.kind != .WORD {
		msg := fmt.tprintf("Unexptected token,%s", TokenKind.WORD)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
	}
	for_cmd.variable = p.curr_token.text
	advance_token(p)

	if !match(p, []TokenKind{.IN}) {
		msg := fmt.tprintf("Unexptected token,%s", TokenKind.IN)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
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
		msg := fmt.tprintf("Unexptected token,%s", TokenKind.DO)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
	}
	skip_newlines(p)

	body, err := parse_cmdlist(p)
	if err.err_type != .None {
		return nil, err
	}
	for_cmd.body = body

	if !match(p, []TokenKind{.DONE}) {
		msg := fmt.tprintf("Unexptected token,%s", p.curr_token.text, true)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
	}

	return for_cmd, ParseError{err_type = .None}
}

parse_if_cmd :: proc(p: ^Parser) -> (^IfClause, ParseError) {
	parse_if :: proc(p: ^Parser, if_cmd: ^IfClause) -> ParseError {
		condition, err := parse_cmdlist(p)
		if err.err_type != .None {
			return err
		}

		if_cmd.condition = condition

		if match(p, []TokenKind{.SEMICOLON}) {
		}

		skip_newlines(p)

		if !match(p, []TokenKind{.THEN}) {
			msg := fmt.tprintf("Unexptected token,%s", TokenKind.THEN)
			return ParseError{err_type = .Unexpected_Token, msg = msg}
		}

		if_cmd.then_branch, err = parse_cmdlist(p)
		if err.err_type != .None {
			return err
		}


		return ParseError{err_type = .None}
	}

	advance_token(p)

	if_clause := new(IfClause)

	if err := parse_if(p, if_clause); err.err_type != .None {
		return nil, err
	}

	curr_if := if_clause

	for match(p, []TokenKind{.ELIF}) {
		elif_clause := new(IfClause)

		if err := parse_if(p, elif_clause); err.err_type != .None {
			return nil, err
		}
		curr_if.else_branch = elif_clause

		curr_if = elif_clause
	}

	if match(p, []TokenKind{.ELSE}) {
		skip_newlines(p)

		else_body, err := parse_cmdlist(p)
		if err.err_type != .None {
			return nil, err
		}

		curr_if.else_branch = else_body
	}

	if p.curr_token.kind != .FI {
	}
	if !match(p, []TokenKind{.FI}) {
		msg := fmt.tprintf("Expected token:%s", TokenKind.FI)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
	}

	return if_clause, ParseError{err_type = .None}
}

parse_bracecmd :: proc(p: ^Parser) -> (^BraceGroup, ParseError) {
	advance_token(p)

	b := new(BraceGroup)

	body, err := parse_cmdlist(p)
	if err.err_type != .None {
		return nil, err
	}
	b.body = body

	if !match(p, []TokenKind{.RIGHTBRACE}) {
		msg := fmt.tprintf("Unexptected token,%s", p.curr_token.text, true)
		return nil, ParseError{err_type = .Unexpected_Token, msg = msg}
	}

	return b, ParseError{err_type = .None}
}

