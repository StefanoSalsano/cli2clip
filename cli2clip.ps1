# cli2clip -- run a block of shell commands, show the output, then offer to put
#             it in the clipboard.
#
# Dot-source this file from your PowerShell profile:
#
#     . "$HOME\.cli2clip.ps1"
#
# Usage:
#
#     cli2clip {
#         git status --short
#         git log --oneline -3
#     }
#
# The output is printed as it happens and captured to a temporary file. When the
# whole block has finished, and only then, you are asked whether to copy it to
# the clipboard: the clipboard stays free while the commands run, which matters
# when a block takes a while and you need to paste something else meanwhile.
#
# On Windows the clipboard is the local one and Set-Clipboard just works, so
# unlike the bash version there is no tmux involved and no fallback needed.
#
# https://github.com/StefanoSalsano/cli2clip -- MIT licensed

function cli2clip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [scriptblock] $Block
    )

    $f = Join-Path $env:TEMP ("cli2clip-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + ".txt")

    # Echo each command above its own output: without it, several commands
    # producing similar output are indistinguishable once pasted somewhere else.
    # The parser gives us the top-level statements with their original text, so
    # a multi-line foreach or if is one statement and stays intact -- no
    # guessing needed. Statements are dot-sourced so that a variable set by one
    # is visible to the next.
    #
    # *>&1 folds every stream into the output -- errors, warnings and, crucially,
    # the information stream that Write-Host writes to. With the error stream
    # alone the labels a block prints with Write-Host reach the screen but not
    # the capture, so the pasted transcript shows "==== Write-Host ..." with
    # nothing under it (found 26/8/2026, on blocks using Write-Host as section
    # headings). What the terminal showed is what belongs in the clipboard.
    # Cost: Write-Host -ForegroundColor loses its colour, the text now travels
    # through the pipeline.
    $statements = $null
    try { $statements = $Block.Ast.EndBlock.Statements } catch { }

    if ($statements -and $statements.Count -gt 0) {
        & {
            foreach ($st in $statements) {
                Write-Output ""
                Write-Output "==== $($st.Extent.Text)"
                . ([scriptblock]::Create($st.Extent.Text))
            }
        } *>&1 | Tee-Object -FilePath $f
    } else {
        & $Block *>&1 | Tee-Object -FilePath $f
    }

    # Discard whatever was typed while the block was running. A block can take
    # minutes, and keystrokes that land in the console meanwhile stay queued: the
    # question below would take the first of them as the answer, declining the
    # copy for a paste the user never meant as a reply.
    #
    # [Console]::KeyAvailable and [Console]::ReadKey are used as a pair on
    # purpose. RawUI.KeyAvailable also reports events that are not key presses --
    # key releases, window and mouse events -- while RawUI.ReadKey with
    # IncludeKeyDown discards those and keeps waiting for a real key, so the two
    # together can block here instead of draining. KeyAvailable throws when the
    # input is redirected, hence the try.
    try {
        while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
    } catch { }

    Write-Host ""
    Write-Host "copy output to clipboard?  [Enter, y, Y] yes, any other key no: " -NoNewline

    # Copying is the common case, so it gets the reflex key: Enter confirms,
    # anything else declines. 'y' is accepted as well, because that is what
    # fingers type at a yes/no question, and having it mean *no* was a trap.
    # Single keypress when the host supports it, with a line-based fallback for
    # hosts that have no raw UI (ISE, remoting, redirected input) -- there an
    # empty line means Enter, same semantics.
    $copy = $false
    try {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        # -eq on strings is case-insensitive in PowerShell, so 'Y' is covered too.
        $copy = ($key.VirtualKeyCode -eq 13) -or ("$($key.Character)" -eq 'y')
        Write-Host ""
    } catch {
        $answer = Read-Host
        $copy = [string]::IsNullOrEmpty($answer) -or ($answer -eq 'y')
    }

    if ($copy) {
        if (Test-Path $f) {
            Get-Content -Path $f -Raw | Set-Clipboard
            $lines = (Get-Content -Path $f | Measure-Object -Line).Lines
            $bytes = (Get-Item $f).Length
            Write-Host "copied: $lines lines, $bytes bytes"
        } else {
            Write-Host "nothing captured"
        }
    } else {
        Write-Host "not copied; output kept in $f"
    }
}
