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
# It refuses to run outside tmux, or with tmux set-clipboard off, because in
# both cases the output could not reach the clipboard -- see below. To run a
# block anyway, with no clipboard and no question:
#
#     cli2clip --no-tmux <<'EOF'
#     ...
#     EOF
#
# `cli2clip --version` prints the version and the path this file was loaded
# from, and `cli2clip --update` replaces ~/.cli2clip.sh with the current one
# from GitHub. Both are answered before the tmux check, so they work anywhere.
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
# OSC 52 (Windows Terminal, iTerm2, kitty, foot, recent xterm, ...). Those
# conditions are checked before the block runs, not after: see the guard.
#
# https://github.com/StefanoSalsano/cli2clip -- MIT licensed

# One version for the project, carried by both scripts and bumped in the same
# commit as any change to either -- see CLAUDE.md. The path is recorded next to
# it because on a machine with several copies around ("the repo one or the
# installed one?") the path is half the answer to "which version am I running".
_cli2clip_was=${_CLI2CLIP_VERSION:-unknown}
_CLI2CLIP_VERSION='1.2.0'
_CLI2CLIP_SOURCE=${BASH_SOURCE[0]}

# Where `--update` downloads from. It is a constant and not a setting: the one
# thing that must stay visible is which URL the update came from, and a value
# that can be overridden quietly defeats that.
_CLI2CLIP_URL='https://raw.githubusercontent.com/StefanoSalsano/cli2clip/main/cli2clip.sh'

# Say so when the file is sourced a second time. The first load, from .bashrc,
# stays silent; a reload after editing or updating the file is the moment you
# want a confirmation, and it answers both halves of the question you actually
# have: WHICH copy did I load (the path -- repo or installed, the usual
# mistake) and DID THE UPDATE ARRIVE (the version, and the one it replaced).
# The previous number is still in the environment at this point, which is what
# makes the second half free.
if declare -F cli2clip >/dev/null 2>&1; then
	if [ "$_cli2clip_was" = "$_CLI2CLIP_VERSION" ]; then
		echo "cli2clip: reloaded $_CLI2CLIP_VERSION from $_CLI2CLIP_SOURCE"
	else
		echo "cli2clip: reloaded $_CLI2CLIP_VERSION (was $_cli2clip_was) from $_CLI2CLIP_SOURCE"
	fi
fi
unset _cli2clip_was

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

# Download the current script and replace the installed copy.
#
# This buys robustness over re-running the README's install snippet, not
# safety: same URL, same TLS, same trust in GitHub, and no signature either
# way. What it does buy is that the download is validated -- non-empty, and
# accepted by `bash -n` -- BEFORE it replaces anything, where `curl -o` writes
# straight onto the installed copy and a truncated transfer leaves you with a
# broken one. The URL is printed every time for the opposite reason: unlike the
# snippet, which you paste from a page you are looking at, here the address
# comes from the copy already on disk, so it has to be shown rather than
# trusted silently.
#
# It updates ~/.cli2clip.sh, the documented install path, and never the file
# this shell happened to load: sourcing a git clone and then updating would
# overwrite uncommitted work with whatever is on GitHub.
_cli2clip_update() {
	local target=$HOME/.cli2clip.sh tmp new ok=1

	tmp=$(mktemp "${target}.XXXXXX") || return 1
	echo "cli2clip: downloading $_CLI2CLIP_URL"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$_CLI2CLIP_URL" -o "$tmp" || ok=0
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$tmp" "$_CLI2CLIP_URL" || ok=0
	else
		echo "cli2clip: neither curl nor wget found" >&2
		ok=0
	fi

	if [ "$ok" = 0 ]; then
		rm -f "$tmp"
		echo "cli2clip: download failed, $target left untouched" >&2
		return 1
	fi
	if [ ! -s "$tmp" ]; then
		rm -f "$tmp"
		echo "cli2clip: downloaded file is empty, $target left untouched" >&2
		return 1
	fi
	if ! bash -n "$tmp" 2>/dev/null; then
		rm -f "$tmp"
		echo "cli2clip: downloaded file is not valid bash, $target left untouched" >&2
		return 1
	fi

	new=$(sed -n "s/^_CLI2CLIP_VERSION='\(.*\)'\$/\1/p" "$tmp" | head -n1)
	[ -n "$new" ] || new=unknown

	# Same directory as the target, so this is a rename and not a copy: the
	# installed file is either the old one or the new one, never half of it.
	mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }

	echo "cli2clip: $target updated, $_CLI2CLIP_VERSION -> $new"
	if [ "$_CLI2CLIP_SOURCE" != "$target" ]; then
		echo "cli2clip: note, this shell had loaded $_CLI2CLIP_SOURCE, which was not touched"
	fi
	# Load it here, so that the update is one step and not two. A function
	# being redefined by a file it is itself sourcing is fine: the running
	# instance finishes with the body it started with, and the new definitions
	# take effect from the next call. Verified on bash 5.1; NOT tested below
	# bash 4, which is why older shells keep the manual reload -- the boundary
	# is what has been tried, not a known breakage, and the fallback is simply
	# the behaviour this had before.
	if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
		# The reload message printed by the file itself is the confirmation
		# that the new version is the one now loaded.
		. "$target"
	else
		echo "cli2clip: run '. $target' to load it in this shell"
	fi
}

cli2clip() {
	local f ans src prelude script line quoted no_tmux=

	# Refuse before running anything when the clipboard cannot be reached.
	# Checking afterwards is what made this worth fixing: the block runs for
	# minutes, you answer the question, and only then you are told the output
	# stayed in a file -- with nothing to paste into the conversation you were
	# in the middle of.
	#
	# The test is $TMUX -- being inside a tmux client -- and not whether a tmux
	# server answers. `load-buffer -w` sends the OSC 52 to the client's
	# terminal, so from outside a client it can exit 0 and report a copy that
	# never reached the terminal you are looking at. set-clipboard off is the
	# same failure from the other side: the sequence is simply not forwarded.
	# `external` forwards it and is therefore fine; only `off` is fatal.
	# --version is answered before the guard on purpose: the moment you want the
	# version is when you are looking at an unfamiliar machine, which is exactly
	# where tmux may be missing. A guard that hid it there would be useless.
	case "$1" in
		--version)
			printf 'cli2clip %s\nloaded from %s\n' \
				"$_CLI2CLIP_VERSION" "$_CLI2CLIP_SOURCE"
			return 0 ;;
		--update) _cli2clip_update; return $? ;;
		--no-tmux) no_tmux=1; shift ;;
		-*) echo "cli2clip: unknown option $1" >&2; return 2 ;;
	esac
	if [ -z "$no_tmux" ]; then
		if [ -z "$TMUX" ]; then
			printf '%s\n' \
				"cli2clip: not inside tmux, so nothing could be copied." \
				"The clipboard is reached with OSC 52 through tmux; without it the" \
				"block would run and its output would only be kept in a file." \
				"" \
				"    tmux new -A -s main     # start or re-attach, then run the block" \
				"" \
				"To run the block anyway, with no clipboard and no question:" \
				"" \
				"    cli2clip --no-tmux <<'EOF'" \
				"    ..." \
				"    EOF" >&2
			return 1
		fi
		if [ "$(tmux show -gv set-clipboard 2>/dev/null)" = off ]; then
			printf '%s\n' \
				"cli2clip: tmux set-clipboard is off, so nothing could be copied." \
				"" \
				"    tmux set -g set-clipboard on" \
				"" \
				"To run the block anyway, with no clipboard and no question:" \
				"" \
				"    cli2clip --no-tmux <<'EOF'" \
				"    ..." \
				"    EOF" >&2
			return 1
		fi
	fi

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
			script="${script}printf '\n==== %s\n' '${quoted}'
${line}
"
		done <<< "$src"
	else
		script="$src"
	fi

	bash -c "${prelude}
${script}" 2>&1 | tee "$f"

	echo
	if [ -n "$no_tmux" ]; then
		# No clipboard to offer, so no question: a keypress that can only
		# lead to one answer is noise.
		echo "no tmux: output kept in $f"
		return 0
	fi

	# Discard whatever was typed while the block was running. A block can take
	# minutes, and anything that lands in the terminal meanwhile stays queued: the
	# question below would eat its first character as the answer -- declining the
	# copy -- and hand the rest to the shell as a command of its own.
	while IFS= read -r -s -t 0.05 -n 4096 _; do :; done </dev/tty 2>/dev/null

	printf 'copy output to clipboard?  [Enter, y, Y] yes, any other key no: '
	# Read the answer from the terminal, not from stdin: stdin is the heredoc
	# carrying the command block, and it has already been consumed.
	# With -n1, pressing Enter returns an empty string: copying is the common
	# case, so it gets the reflex key. 'y' is accepted too, because that is what
	# fingers type at a yes/no question, and having it mean *no* was a trap.
	read -r -n1 ans </dev/tty
	echo
	if [ -z "$ans" ] || [ "$ans" = y ] || [ "$ans" = Y ]; then
		if tmux load-buffer -w "$f" 2>/dev/null; then
			echo "copied: $(wc -l <"$f") lines, $(wc -c <"$f") bytes"
		else
			echo "no tmux server reachable from here; output kept in $f"
		fi
	else
		echo "not copied; output kept in $f"
	fi
}
