# cli2clip

Run a block of shell commands, watch the output, then decide whether to put it
in the clipboard.

```bash
cli2clip <<'EOF'
git status --short
git log --oneline -3
EOF
```

```
=== output scrolls by as usual ===

copy output to clipboard?  [Enter] yes, any other key no:
copied: 24 lines, 1213 bytes
```

Copying is what you almost always want, so it is bound to the reflex key: press
Enter to copy, any other key to skip.

## Why

It exists for a specific, repetitive situation: you are working with an
assistant, or a colleague, in a chat window, and the loop is always the same —
they give you commands, you run them in a terminal, you have to get the output
back into the chat. Selecting a screenful of text with the mouse, over ssh,
inside tmux, is tedious and error-prone, and it silently truncates.

Two details make the difference:

* **the clipboard is written only at the end, and only if you say so.** A block
  that takes twenty seconds must not hold your clipboard hostage while it runs:
  in those twenty seconds you may well need it for something else;
* **the capture is exact.** It is the real stdout and stderr of the commands,
  not whatever happened to be visible on screen, so nothing is lost to the
  scrollback and nothing extra is picked up.

If you answer no, the capture file is kept and its path printed, so you can
still copy it later.

## Install

Linux, bash. Uses `curl` or `wget`, whichever the machine has — a bare server
often has only one of the two:

```bash
URL=https://raw.githubusercontent.com/StefanoSalsano/cli2clip/main/cli2clip.sh
if   command -v curl >/dev/null 2>&1; then curl -fsSL "$URL" -o ~/.cli2clip.sh
elif command -v wget >/dev/null 2>&1; then wget -qO ~/.cli2clip.sh "$URL"
else echo "cli2clip: neither curl nor wget found" >&2; fi
grep -q cli2clip ~/.bashrc 2>/dev/null || echo '[ -f ~/.cli2clip.sh ] && . ~/.cli2clip.sh' >> ~/.bashrc
. ~/.cli2clip.sh 2>/dev/null
if type cli2clip >/dev/null 2>&1; then
	printf '\ncli2clip is installed and ready.\n\n  cli2clip <<%sEOF%s\n  hostname\n  EOF\n\nEnter copies the output, any other key skips it.\n\n' "'" "'"
else
	echo "cli2clip: installation failed, ~/.cli2clip.sh was not sourced" >&2
fi
```

Windows, PowerShell:

```powershell
$url = 'https://raw.githubusercontent.com/StefanoSalsano/cli2clip/main/cli2clip.ps1'
Invoke-WebRequest -Uri $url -OutFile "$HOME\.cli2clip.ps1"
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
if (-not (Select-String -Path $PROFILE -Pattern cli2clip -Quiet)) { Add-Content $PROFILE '. "$HOME\.cli2clip.ps1"' }
. "$HOME\.cli2clip.ps1"
if (Get-Command cli2clip -ErrorAction SilentlyContinue) {
    Write-Host "`ncli2clip is installed and ready.`n`n  cli2clip { hostname }`n`nEnter copies the output, any other key skips it.`n"
} else {
    Write-Host "cli2clip: installation failed, `$HOME\.cli2clip.ps1 was not sourced" -ForegroundColor Red
}
```

Both are idempotent: running them again updates the script without duplicating
the line in the profile. Both end by checking that the function is actually
defined, so a silent failure — a download that produced an empty file, a profile
that is not read — is reported instead of surfacing later as
`cli2clip: command not found`.

## Telling an assistant to use it

The tool is half of a loop whose other half is the assistant you are talking to
— Claude, ChatGPT, or anything else. It will not know about `cli2clip` on its
own, and it cannot read this repository. Paste the following into the
conversation once, at the start, and it will start producing blocks you can run
as they are:

````
When you need me to run commands and report the output back to you, give me a
single cli2clip block instead of loose commands.

On Linux, bash:

    cli2clip <<'EOF'
    <your commands>
    EOF

On Windows, PowerShell:

    cli2clip { <your commands> }

It runs the block, shows me the output, and when the block has finished it asks
whether to copy it. I press Enter and paste it back to you.

Rules for those blocks:

- one block, ready to paste as it is, with no placeholders for me to fill in;
- begin with an absolute cd, never rely on the directory I happen to be in;
- state in a comment which machine and which shell the block is for, when there
  is more than one;
- add "|| true" where a non-zero exit is expected (grep finding nothing, for
  instance), otherwise it is reported as a failure;
- to create a file, do not paste its contents into the terminal: long pastes
  get mangled, especially through ssh and nested sessions. Give me the file
  another way and a command to put it in place.
````

The last two rules are the ones that repay themselves fastest. Assistants
produce `grep` pipelines constantly, and a false `!! FAILED` on every one of
them trains you to ignore the marker that matters. And a here-document of a
hundred lines pasted through several hops of ssh will, sooner or later, arrive
corrupted in a way that is very hard to notice.

## Usage

The bash version takes the commands on standard input, so use a **quoted**
heredoc (`<<'EOF'`, with the quotes) unless you want the calling shell to expand
things before they are run:

```bash
cli2clip <<'EOF'
for f in /etc/hostname /etc/machine-id; do echo "--- $f"; cat "$f"; done
EOF
```

The PowerShell version takes a script block, which is multi-line by nature:

```powershell
cli2clip {
    Get-ChildItem C:\GITs -Directory | Select-Object Name, LastWriteTime
}
```

Anything the shell can do works inside the block: loops, pipelines, heredocs,
function definitions. The block runs in a subshell, so `cd` and variables set
inside it do not leak into your session.

## Failures

In the bash version every command that exits non-zero is reported where it
fails, without stopping the block:

```
!! FAILED (exit 2): ls /nonexistent
```

A diagnostic block usually wants the remaining commands to run even if one of
them fails, which is why the block is not aborted. Commands whose failure is
already handled stay silent — `grep pattern file || true`, `if cmd; then`,
`a && b` — so the expected non-zero exits of tools like `grep` do not produce
noise.

The PowerShell version does not do this: PowerShell has no equivalent that
catches the exit status of *native* commands without wrapping each one, and
wrapping each one would rule out the multi-line constructs that make the script
block worth using.

## How the clipboard is reached

On Windows, `Set-Clipboard` writes to the local clipboard.

On Linux there is no clipboard to write to — X11 or Wayland may not even be
running on the machine you are logged into. The bash version therefore goes
through **tmux**, which forwards the text to the terminal emulator using the
OSC 52 escape sequence. The clipboard that ends up holding the text is the one
of the machine where your *terminal* runs, which is what you want when you are
working over ssh.

This has two consequences worth knowing:

* it needs a running tmux server on the machine where `cli2clip` runs, and
  `set-clipboard` enabled (`tmux show -g set-clipboard`, set it with
  `tmux set -g set-clipboard on`);
* it needs a terminal emulator that supports OSC 52. Windows Terminal, iTerm2,
  kitty, foot and recent xterm do; some others do not, and a few impose a size
  limit on what they will accept.

If tmux is not reachable, nothing is lost: the capture file stays and its path
is printed.

### Nested sessions

If you are several hops deep — ssh into a host, then into a container, then into
a virtual machine — the innermost shell usually has no tmux server of its own,
and `cli2clip` there will just keep the file. That is expected. The tmux session
you started at the *outer* hop can still see everything that scrolled past, so
capture from there instead:

```bash
tmux capture-pane -p -S -500 | tail -n 100 | tmux load-buffer -w -
```

## License

MIT. See [LICENSE](LICENSE).
