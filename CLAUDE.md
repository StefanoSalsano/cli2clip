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

## Scope

The tmux guard, `--no-tmux` and `--version` are bash-only by design: on Windows
`Set-Clipboard` writes to the local clipboard and none of this applies. Keep the
two scripts parallel where the behaviour is shared, and say so in the README
where it is not.
