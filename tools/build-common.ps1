# Shared by start-game.ps1 and start-editor.ps1: finding the CShift compiler, building a project, starting a program.

function Get-CShiftCompiler {
    if ($env:CSHIFTC -and (Test-Path $env:CSHIFTC)) {
        return $env:CSHIFTC
    }
    $onPath = Get-Command cshiftc -ErrorAction SilentlyContinue
    if ($onPath) {
        return $onPath.Source
    }
    # the place of the compiler beside the repository
    $beside = Join-Path $PSScriptRoot '..\..\Tools\cshiftc.exe'
    if (Test-Path $beside) {
        return (Resolve-Path $beside).Path
    }
    throw 'cshiftc.exe not found: put it on the PATH or set $env:CSHIFTC to its path.'
}

function Invoke-CShiftBuild([string]$project) {
    $compiler = Get-CShiftCompiler
    Write-Host "Building $project ..."
    & $compiler build $project
    if ($LASTEXITCODE -ne 0) {
        throw "The build of $project failed (is the program still running?)."
    }
}

# starts a program with a window and returns at once; with arguments it runs in this console, so that its output
# (test modes like --shot or --selftest) is shown and its exit code is kept
function Start-Program([string]$exe, [string[]]$arguments) {
    if (-not (Test-Path $exe)) {
        throw "$exe does not exist: start without -NoBuild to build it."
    }
    if ($arguments -and $arguments.Count -gt 0) {
        & $exe @arguments
        exit $LASTEXITCODE
    }
    Start-Process -FilePath $exe -WorkingDirectory (Get-Location).Path
}
