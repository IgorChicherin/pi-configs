$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$originalHome = $HOME
$originalAgentDir = $env:PI_CODING_AGENT_DIR
$global:FakePiExit = 0
$global:FakePiCalls = @()
$global:FakeNpxExit = 0
$global:FakeNpxCalls = @()

function global:pi {
    $global:FakePiCalls += ($args -join ' ')
    $global:LASTEXITCODE = $global:FakePiExit
}
function global:npx {
    $global:FakeNpxCalls += ($args -join ' ')
    $global:LASTEXITCODE = $global:FakeNpxExit
}
function Assert($condition, $message) {
    if (-not $condition) { throw $message }
}

try {
    $env:PI_CODING_AGENT_DIR = $null
    $testHome = Join-Path $temp 'home with spaces'
    New-Item -ItemType Directory -Path $testHome -Force | Out-Null
    Set-Variable HOME -Value $testHome -Force -Scope Global
    & $installer
    $agent = Join-Path $HOME '.pi/agent'
    Assert (@(Get-ChildItem -LiteralPath $agent -File).Count -eq 4) 'Expected four copied config files'
    Assert ($global:FakePiCalls.Count -eq 1) 'Expected one Pi call'
    Assert ($global:FakePiCalls[0] -eq 'update --extensions') 'Unexpected Pi command'
    Assert ($global:FakeNpxCalls.Count -eq 1) 'Expected one skills install'
    Assert ($global:FakeNpxCalls[0] -eq '--yes skills add mattpocock/skills --global --agent pi --skill * --yes') 'Unexpected skills command'
    foreach ($file in Get-ChildItem -LiteralPath $agent -File) {
        Assert (-not ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) 'Expected copies, not links'
    }

    $conflictHome = Join-Path $temp 'conflict'
    $conflictAgent = Join-Path $conflictHome '.pi/agent'
    New-Item -ItemType Directory -Path $conflictAgent -Force | Out-Null
    $existing = Join-Path $conflictAgent 'settings.json'
    [System.IO.File]::WriteAllText($existing, '{"keep":true}')
    Set-Variable HOME -Value $conflictHome -Force -Scope Global
    $failed = $false
    try { & $installer } catch { $failed = $_.Exception.Message -like 'Config already exists:*' }
    Assert $failed 'Expected conflict rejection'
    Assert (([System.IO.File]::ReadAllText($existing)) -eq '{"keep":true}') 'Existing config changed'
    Assert (@(Get-ChildItem -LiteralPath $conflictAgent -File).Count -eq 1) 'Conflict caused partial deployment'
    Assert ($global:FakePiCalls.Count -eq 1) 'Pi ran despite conflict'
    Assert ($global:FakeNpxCalls.Count -eq 1) 'Skills installed despite conflict'

    $failureHome = Join-Path $temp 'plugin failure'
    New-Item -ItemType Directory -Path $failureHome -Force | Out-Null
    Set-Variable HOME -Value $failureHome -Force -Scope Global
    $global:FakePiExit = 7
    $failed = $false
    try { & $installer } catch { $failed = $_.Exception.Message -like 'Plugin installation failed*' }
    Assert $failed 'Expected plugin failure to propagate'
    Assert (Test-Path (Join-Path $HOME '.pi/agent/settings.json')) 'Config missing after plugin failure'
    Assert ($global:FakeNpxCalls.Count -eq 1) 'Skills installed despite plugin failure'

    $skillFailureHome = Join-Path $temp 'skill failure'
    New-Item -ItemType Directory -Path $skillFailureHome -Force | Out-Null
    Set-Variable HOME -Value $skillFailureHome -Force -Scope Global
    $global:FakePiExit = 0
    $global:FakeNpxExit = 8
    $failed = $false
    try { & $installer } catch { $failed = $_.Exception.Message -like 'Skill installation failed*' }
    Assert $failed 'Expected skill failure to propagate'
    Assert (Test-Path (Join-Path $HOME '.pi/agent/settings.json')) 'Config missing after skill failure'
    Write-Host 'PASS: Windows copy, skill installation, conflicts, and failure reporting'
} finally {
    Set-Variable HOME -Value $originalHome -Force -Scope Global
    $env:PI_CODING_AGENT_DIR = $originalAgentDir
    Remove-Item function:pi, function:npx
    Remove-Variable FakePiExit, FakePiCalls, FakeNpxExit, FakeNpxCalls -Scope Global
    Remove-Item -LiteralPath $temp -Recurse -Force
}
