package execute


import posix "core:sys/posix"

Signal :: struct {
	sig_child:     b32,
	window_resize: b32,
}

g_sig: Signal

@(private)
sigchld_handler :: proc "c" (sig: posix.Signal) {
	g_sig.sig_child = true
}

@(private)
sigwinch_handler :: proc "c" (sig: posix.Signal) {
	g_sig.window_resize = true
}


setup_signals :: proc() {
	sa: posix.sigaction_t

	posix.sigemptyset(&sa.sa_mask)

	sa.sa_flags = {}
	//TODO : handle setup error
	sa.sa_handler = sigchld_handler
	if posix.sigaction(.SIGCHLD, &sa, nil) != .OK {
	}

	sa.sa_handler = sigwinch_handler
	if posix.sigaction(auto_cast 28, &sa, nil) != .OK {
	}

}

unset_signal :: proc() {
	if g_sig.sig_child do g_sig.sig_child = false
	if g_sig.window_resize do g_sig.window_resize = false
}

