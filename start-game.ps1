# Builds Shifty Bits (desktop) and starts it.
#
#   .\start-game.ps1                  build, then start
#   .\start-game.ps1 -NoBuild         start bin\ShiftyBits.exe as it is
#   .\start-game.ps1 --fullscreen     further arguments go to the game
#
# The compiler is taken from $env:CSHIFTC, from the PATH, or from ..\Tools\cshiftc.exe.

param(
    [switch]$NoBuild,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GameArgs
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\tools\build-common.ps1"

# the game reads song.txt and shiftybits-best.txt from the folder it is started in
Set-Location $PSScriptRoot
if (-not $NoBuild) {
    Invoke-CShiftBuild '.'
}
Start-Program 'bin\ShiftyBits.exe' $GameArgs
