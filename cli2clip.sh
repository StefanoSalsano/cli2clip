# cli2clip -- run a block of shell commands, show the output, then offer to put
#             it in the clipboard.
#
# Source this file from ~/.bashrc:
#
#     [ -f ~/.cli2clip.sh ] && . ~/.cli2clip.sh
#
# Usage:
#
#     cli2clip <<'EOF'
#     git status --short
#     git log --oneline -3
#     EOF
#
# The output is printed as it happens and captured to a temporary file. When the
# whole block has finished, and only then, you are asked whether to copy it to
# the clipboard: the clipboard stays free while the commands run, which matters
# when a block takes a while and you need to paste something else meanwhile.
#
# Clipboard support on Linux goes through tmux, which forwards the text to the
# terminal emulator with the OSC 52 escape sequence. This means the clipboard
# reached is the one of the machine where your *terminal* runs, not the one of
# the machine where the commands run -- which is the point when you are working
# over ssh. It requires a running tmux server and a terminal that supports
# OSC 52 (Windows Terminal, iTerm2, kitty, foot, recent xterm, ...). If tmux is
# not reachable, the capture file is kept and its path is printed.
#
# https://github.com/StefanoSalsano/cli2clip -- MIT licensed

# Can the block be split into one command per line?
#
# When it can, each command is echoed above its own output, which is what makes
# a pasted transcript readable: without it, several commands producing similar
# output are indistinguishable. When it cannot -- multi-line loops, here
# documents, line continuations -- the block is run as a whole and the labels
# are dropped. Labels are a convenience; running the block correctly is not.
_cli2clip_decomposable() {
	local line stripped
	while IFS= read -r line; do
		case "$line" in ''|\#*) continue ;; esac

		# A here document swallows the lines that follow it, so the block
		# cannot be split. `<<<` is a here string and is harmless, so remove
		# those before looking for `<<`.
		stripped=${line//<<</}
		case "$stripped" in *'<<'*) return 1 ;; esac

		# A trailing backslash continues onto the next line.
		case "$line" in *\\) return 1 ;; esac

		# Anything else that is not a complete command on its own: `for ... do`,
		# `if ... then`, an unclosed quote, and so on.
		bash -n -c "$line" 2>/dev/null || return 1
	done <<< "$1"
	return 0
}

cli2clip() {
	local f ans src prelude script line quoted

	f=$(mktemp /tmp/cli2clip-XXXXXX.txt) || return 1
	src=$(cat)

	# Report every command that exits non-zero, at the point where it fails,
	# without stopping the block: in a diagnostic block you normally want the
	# remaining commands to run anyway. The ERR trap does not fire for commands
	# whose failure is already handled (`... || true`, `if ...`, `a && b`), so
	# an expected non-zero exit stays silent.
	prelude='set -E; trap '\''echo "!! FAILED (exit $?): $BASH_COMMAND" >&2'\'' ERR'

	if _cli2clip_decomposable "$src"; then
		# Build one script that prints each command before running it. It has to
		# be a single script, not one shell per line: otherwise a variable set
		# on one line, or a `cd`, would be lost by the next one.
		script=""
		while IFS= read -r line; do
			case "$line" in ''|\#*) continue ;; esac
			quoted=${line//\'/\'\\\'\'}
			script="${script}printf '\n════ %s\n' '${quoted}'
${line}
"
		done <<< "$src"
	else
		script="$src"
	fi

	bash -c "${prelude}
${script}" 2>&1 | tee "$f"

	echo
	# Discard whatever was typed while the block was running. A block can take
	# minutes, and anything that lands in the terminal meanwhile stays queued: the
	# question below would eat its first character as the answer -- declining the
	# copy -- and hand the rest to the shell as a command of its own.
	while IFS= read -r -s -t 0.05 -n 4096 _; do :; done </dev/tty 2>/dev/null

	printf 'copy output to clipboard?  [Enter] yes, any other key no: '
	# Read the answer from the terminal, not from stdin: stdin is the heredoc
	# carrying the command block, and it has already been consumed.
	# With -n1, pressing Enter returns an empty string: copying is the common
	# case, so it gets the reflex key.
	read -r -n1 ans </dev/tty
	echo
	if [ -z "$ans" ]; then
		if tmux load-buffer -w "$f" 2>/dev/null; then
			echo "copied: $(wc -l <"$f") lines, $(wc -c <"$f") bytes"
		else
			echo "no tmux server reachable from here; output kept in $f"
		fi
	else
		echo "not copied; output kept in $f"
	fi
}
