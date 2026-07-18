# shell

A minimal POSIX shell written in Odin. The execution engine uses a virtual arena allocator for the AST to improve cache locality and simplify memory cleanup per command.

## To run:
```bash
odin run src
