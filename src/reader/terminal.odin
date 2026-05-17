package reader

import posix "core:sys/posix"

@(private = "file")
termios: posix.termios


enable_raw_mode :: proc() {
	result := posix.tcgetattr(posix.STDIN_FILENO, &termios)
	assert(result == .OK)

	raw := termios
	raw.c_iflag -= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
	raw.c_lflag -= {.ECHO, .ICANON, .IEXTEN}
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 1

	result = posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw)
	assert(result == .OK)


}

disable_raw_mode :: proc() {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &termios)
}

