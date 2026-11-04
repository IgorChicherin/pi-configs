$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$originalHome = $HOME
$originalAgentDir = $env:PI_CODING_AGENT_DIR
$originalLspAgentDir = $env:PI_AGENT_DIR
$originalEnvHome = $env:HOME
$global:FakePiExit = 0
$global:FakePiCalls = @()
$global:FakeNpmExit = 0
$global:FakeNpmCalls = @()
$global:FakeNpxExit = 0
$global:FakeNpxCalls = @()

function global:pi {
    $global:FakePiCalls += ($args -join ' ')
    $global:LASTEXITCODE = $global:FakePiExit
}
function global:npm {
    $global:FakeNpmCalls += ($args -join ' ')
    $global:LASTEXITCODE = $global:FakeNpmExit
}
function global:npx {
    $global:FakeNpxCalls += ($args -join ' ')
    $global:LASTEXITCODE = $global:FakeNpxExit
}
function Set-TestHome($path) {
    Set-Variable HOME -Value $path -Force -Scope Global
    $env:PI_AGENT_DIR = Join-Path $path '.pi/agent'
}
function Assert($condition, $message) {
    if (-not $condition) { throw $message }
}

try {
    $env:PI_CODING_AGENT_DIR = $null
    $testHome = Join-Path $temp 'home with spaces'
    New-Item -ItemType Directory -Path $testHome -Force | Out-Null
    Set-TestHome $testHome
    $env:PI_AGENT_DIR = $null
    $env:HOME = $null
    $failed = $false
    try { & $installer } catch { $failed = $_.Exception.Message -like 'pi-lsp requires PI_AGENT_DIR*' }
    Assert $failed 'Expected missing Windows LSP config discovery environment to be rejected'
    Assert (-not (Test-Path (Join-Path $HOME '.pi'))) 'Environment failure deployed configs'
    Set-TestHome $testHome
    & $installer
    $agent = Join-Path $HOME '.pi/agent'
    Assert (@(Get-ChildItem -LiteralPath $agent -File).Count -eq 5) 'Expected five copied config files'
    Assert (Test-Path (Join-Path $agent 'lsp.json')) 'Expected LSP configuration'
    Assert ($global:FakeNpmCalls.Count -eq 1) 'Expected one LSP server install'
    Assert ($global:FakeNpmCalls[0] -eq "install --prefix $(Join-Path $agent 'lsp-servers') --no-save --package-lock=false --ignore-scripts basedpyright yaml-language-server vscode-langservers-extracted") 'Unexpected LSP server command'
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
    Set-TestHome $conflictHome
    $failed = $false
    try { & $installer } catch { $failed = $_.Exception.Message -like 'Config already exists:*' }
    Assert $failed 'Expected conflict rejection'
    Assert (([System.IO.File]::ReadAllText($existing)) -eq '{"keep":true}') 'Existing config changed'
    Assert (@(Get-ChildItem -LiteralPath $conflictAgent -File).Count -eq 1) 'Conflict caused partial deployment'
    Assert ($global:FakePiCalls.Count -eq 1) 'Pi ran despite conflict'
    Assert ($global:FakeNpxCalls.Count -eq 1) 'Skills installed despite conflict'

    $failureHome = Join-Path $temp 'plugin failure'
    New-Item -ItemType Directory -Path $failureHome -Force | Out-Null
    Set-TestHome $failureHome
    $global:FakePiExit = 7
    $failed = $false
    try { & $installer } catch { $failed = $_.Exception.Message -like 'Plugin installation failed*' }
    Assert $failed 'Expected plugin failure to propagate'
    Assert (Test-Path (Join-Path $HOME '.pi/agent/settings.json')) 'Config missing after plugin failure'
    Assert ($global:FakeNpxCalls.Count -eq 1) 'Skills installed despite plugin failure'

    $lspFailureHome = Join-Path $temp 'lsp failure'
    New-Item -ItemType Directory -Path $lspFailureHome -Force | Out-Null
    Set-TestHome $lspFailureHome
    $global:FakePiExit = 0
    $global:FakeNpmExit = 9
    $failed = $false
    try { & $installer } catch { $failed = $_.Exception.Message -like 'LSP server installation failed*' }
    Assert $failed 'Expected LSP server failure to propagate'
    Assert (Test-Path (Join-Path $HOME '.pi/agent/lsp.json')) 'Config missing after LSP server failure'
    Assert ($global:FakeNpxCalls.Count -eq 1) 'Skills installed despite LSP server failure'
    $global:FakeNpmExit = 0

    $skillFailureHome = Join-Path $temp 'skill failure'
    New-Item -ItemType Directory -Path $skillFailureHome -Force | Out-Null
    Set-TestHome $skillFailureHome
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
    $env:PI_AGENT_DIR = $originalLspAgentDir
    $env:HOME = $originalEnvHome
    Remove-Item function:pi, function:npm, function:npx
    Remove-Variable FakePiExit, FakePiCalls, FakeNpmExit, FakeNpmCalls, FakeNpxExit, FakeNpxCalls -Scope Global
    Remove-Item -LiteralPath $temp -Recurse -Force
}
