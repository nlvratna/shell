package parser

// import "core:testing"
//
// @(private)
// setup_and_parse :: proc(t: ^testing.T, input: string) -> ^SimpleCommand {
// 	p: Parser
// 	parser_init(&p, input)
//
// 	parser_event := parse(&p)
// 	program := parser_event.program
// 	testing.expect_value(t, parser_event.parse_err, "")
// 	testing.expect_value(t, len(program.cmds), 1)
//
// 	cmd, ok := program.cmds[0].(^SimpleCommand)
// 	testing.expect(t, ok, "Expected the AST node to be a SimpleCommand")
//
// 	return cmd
// }
//
// @(test)
// test_parse_background_jobs :: proc(t: ^testing.T) {
// 	cmd := setup_and_parse(t, "sleep 5 &")
//
// 	testing.expect_value(t, len(cmd.words), 2)
// 	testing.expect_value(t, cmd.words[0], "sleep")
// 	testing.expect_value(t, cmd.words[1], "5")
//
// 	testing.expect_value(t, cmd.is_bg, true)
// }
//
// @(test)
// test_parse_env_assignments :: proc(t: ^testing.T) {
// 	cmd := setup_and_parse(t, "DEBUG=1 PORT=8080 ./server --prod")
//
// 	testing.expect_value(t, len(cmd.assigns), 2)
// 	testing.expect_value(t, cmd.assigns[0], "DEBUG=1")
// 	testing.expect_value(t, cmd.assigns[1], "PORT=8080")
//
// 	testing.expect_value(t, len(cmd.words), 2)
// 	testing.expect_value(t, cmd.words[0], "./server")
// 	testing.expect_value(t, cmd.words[1], "--prod")
// }
//
// @(test)
// test_parse_redirections :: proc(t: ^testing.T) {
// 	cmd := setup_and_parse(t, "grep \"error\" < app.log > issues.txt")
//
// 	testing.expect_value(t, len(cmd.words), 2)
// 	testing.expect_value(t, cmd.words[0], "grep")
// 	testing.expect_value(t, cmd.words[1], "error") //these are stripped
//
// 	testing.expect_value(t, len(cmd.redirects), 2)
//
// 	testing.expect_value(t, cmd.redirects[0].kind, TokenKind.LESS)
// 	testing.expect_value(t, cmd.redirects[0].file, "app.log")
//
// 	testing.expect_value(t, cmd.redirects[1].kind, TokenKind.GREATER)
// 	testing.expect_value(t, cmd.redirects[1].file, "issues.txt")
// }
//
// @(test)
// test_parse_the_kitchen_sink :: proc(t: ^testing.T) {
// 	cmd := setup_and_parse(t, "RUST_LOG=info cargo run < input.json >> append.log &")
//
// 	testing.expect_value(t, len(cmd.assigns), 1)
// 	testing.expect_value(t, cmd.assigns[0], "RUST_LOG=info")
//
// 	testing.expect_value(t, len(cmd.words), 2)
// 	testing.expect_value(t, cmd.words[0], "cargo")
// 	testing.expect_value(t, cmd.words[1], "run")
//
// 	testing.expect_value(t, len(cmd.redirects), 2)
// 	testing.expect_value(t, cmd.redirects[0].kind, TokenKind.LESS)
// 	testing.expect_value(t, cmd.redirects[1].kind, TokenKind.DGREAT) // Assuming DGREAT is '>>'
//
// 	testing.expect_value(t, cmd.is_bg, true)
// }
