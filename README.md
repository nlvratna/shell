# shell

A minimal POSIX shell written in Odin. 

This project implements core shell mechanics including system binary execution, standard I/O redirection, and background job control. The execution engine uses a frame-based virtual arena allocator for the Abstract Syntax Tree (AST) to ensure cache locality and simplified memory cleanup per command.

## Usage

```bash
odin run src
```

## Acknowledgments

The architecture and parsing logic rely on standard systems programming references and compiler literature:

* **[Crafting Interpreters](https://craftinginterpreters.com/)** (Robert Nystrom) & **[Writing An Interpreter in Go](https://interpreterbook.com/)** (Thorsten Ball): AST structure and recursive-descent parsing theory.
* **[Titania Tokenizer](https://github.com/gingerBill/titania/blob/master/src/tokenizer.odin)** (Ginger Bill): Tokenizer core loop and idiomatic Odin patterns.
* **[The Linux Programming Interface](https://man7.org/tlpi/)** (Michael Kerrisk): Process control (`fork`/`execvp`), signal handling, and file descriptor management.
