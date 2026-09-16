# cli2clip -- working rules for this repository

## Versioning

`cli2clip.sh` and `cli2clip.ps1` share **one project version**: `_CLI2CLIP_VERSION`
in the shell script, a `# Version:` line in the PowerShell one. **Bump it in the
same commit as any change to either script, in both files.**

Why this is worth the discipline, and not a formality to optimise away: the
number's only job is to answer *"which copy is running on this machine"*. There
is no package manager here -- installing is a `curl` into `~/.cli2clip.sh` on
whatever host needed it -- so a copy sitting on a remote machine cannot be
compared with the repository in any other way. A number bumped one commit late
points at the wrong code, which is worse than no number at all: it is believed.

Patch for a fix, minor for a new option or a behaviour change. This is not a
release process: there are no tags and no changelog, and adding them is not
implied by the rule.

## Who runs git

Commits, pushes and any other git command are run by Stefano from PowerShell,
never by a Cowork session from the sandbox (skill `git-repo-rules`). A session
edits the files and hands over a ready-to-paste block.

## Verifying a change to the bash script

The option parsing and the tmux guard can be exercised without a terminal:
source the script in a plain bash shell, stub `tmux` with a shell function, and
check the exit codes and the messages. That proves the *logic*; it does not
prove the interaction with a real tmux server, nor anything about the clipboard
actually reaching a terminal. When reporting the check, say which of the two you
did -- a "verified" that silently means the first one is how a defect survives.

## Testing a change to `--update`

**The code that performs an update is always the previous version's.** Jumping a
machine to version N exercises N-1's `--update`; the behaviour introduced in N
only shows on the jump *after* that. So the first run on a host proves nothing
about what you just changed -- run it twice, or the second run is the test.

The same applies to the option existing at all: a host on a version older than
the one that added `--update` has to be moved with the README's curl snippet
first. Both halves of this bit us on 16/9/2026, the second time within an hour
of noticing the first.

## Scope

The tmux guard, `--no-tmux` and `--version` are bash-only by design: on Windows
`Set-Clipboard` writes to the local clipboard and none of this applies. Keep the
two scripts parallel where the behaviour is shared, and say so in the README
where it is not.
