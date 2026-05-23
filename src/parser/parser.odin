package parser

import "core:mem/virtual"

Parser :: struct {
	arena:      virtual.Arena, //is this good?
	data:       string,
	t:          Tokenizer,
	prev_token: Token,
	curr_token: Token,
}


parser_ini :: proc(data: string) -> ^Parser {
	p := new(Parser)

	tokenizer_ini(&p.t, data)
	advance_token(p)
	return p
}

advance_token :: proc(p: ^Parser) -> Token {
	p.prev_token = p.curr_token
	p.curr_token = get_token(&p.t)

	return p.prev_token
}

