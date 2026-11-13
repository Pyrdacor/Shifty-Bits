# Builds the Shifty Bits music editor and starts it with song.txt of this folder.
#
#   .\start-editor.ps1                build, then start
#   .\start-editor.ps1 -NoBuild       start tools\musiceditor\bin\MusicEditor.exe as it is
#   .\start-editor.ps1 other.txt      further arguments go to the editor (here: another song file)
#
# The compiler is taken from $env:CSHIFTC, from the PATH, or from ..\Tools\cshiftc.exe.

param(
    [switch]$NoBuild,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$EditorArgs
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\tools\build-common.ps1"

# the editor looks for song.txt in the folder it is started in
Set-Location $PSScriptRoot
if (-not $NoBuild) {
    Invoke-CShiftBuild 'tools\musiceditor'
}
Start-Program 'tools\musiceditor\bin\MusicEditor.exe' $EditorArgs
