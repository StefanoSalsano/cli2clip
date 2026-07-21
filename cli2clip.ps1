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

    # 2>&1 folds the error stream into the output so that failures are captured
    # too, instead of only appearing on screen.
    & $Block 2>&1 | Tee-Object -FilePath $f

    Write-Host ""
    Write-Host "copy output to clipboard?  [Enter] yes, any other key no: " -NoNewline

    # Copying is the common case, so it gets the reflex key: Enter confirms,
    # anything else declines. Single keypress when the host supports it, with a
    # line-based fallback for hosts that have no raw UI (ISE, remoting,
    # redirected input) -- there an empty line means Enter, same semantics.
    $copy = $false
    try {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $copy = ($key.VirtualKeyCode -eq 13)
        Write-Host ""
    } catch {
        $copy = [string]::IsNullOrEmpty((Read-Host))
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
