$ErrorActionPreference = 'Stop'

foreach ($command in @('pi', 'npm', 'npx')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command missing: $command"
    }
}
if ($env:PI_CODING_AGENT_DIR) {
    throw 'Unset PI_CODING_AGENT_DIR; this installer targets ~/.pi/agent.'
}

$source = Join-Path $PSScriptRoot 'pi/.pi/agent'
$target = Join-Path $HOME '.pi/agent'
# pi-lsp 0.1.7 does not fall back to USERPROFILE on Windows.
$lspAgentDir = $env:PI_AGENT_DIR
if (-not $lspAgentDir -and $env:HOME) {
    $lspAgentDir = Join-Path $env:HOME '.pi/agent'
}
if (-not $lspAgentDir -or [System.IO.Path]::GetFullPath($lspAgentDir) -ne [System.IO.Path]::GetFullPath($target)) {
    throw 'pi-lsp requires PI_AGENT_DIR pointing to ~/.pi/agent (or HOME matching your profile). See README.md Windows setup; restart your terminal afterward.'
}
$files = @(Get-ChildItem -LiteralPath $source -File)

# Check every destination before copying anything.
foreach ($directory in @((Join-Path $HOME '.pi'), $target)) {
    if ((Test-Path -LiteralPath $directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Not a directory: $directory"
    }
}
foreach ($file in $files) {
    $destination = Join-Path $target $file.Name
    if (Test-Path -LiteralPath $destination) {
        throw "Config already exists: $destination. Back it up and move it aside first."
    }
}

New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($file in $files) {
    # Copy without overwrite, even if a file appeared after the checks above.
    [System.IO.File]::Copy($file.FullName, (Join-Path $target $file.Name), $false)
}

Push-Location $HOME
try {
    & pi update --extensions
    if ($LASTEXITCODE -ne 0) {
        throw "Plugin installation failed (exit $LASTEXITCODE). Configs remain installed; retry: pi update --extensions"
    }
    & npm install --prefix (Join-Path $target 'lsp-servers') --no-save --package-lock=false --ignore-scripts basedpyright yaml-language-server vscode-langservers-extracted
    if ($LASTEXITCODE -ne 0) {
        throw "LSP server installation failed (exit $LASTEXITCODE). Configs remain installed; see README.md for retry command."
    }
    & npx --yes skills add mattpocock/skills --global --agent pi --skill '*' --yes
    if ($LASTEXITCODE -ne 0) {
        throw "Skill installation failed (exit $LASTEXITCODE). Retry: npx --yes skills add mattpocock/skills --global --agent pi --skill '*' --yes"
    }
    & npx --yes skills add evgenyigumnov/subtask4llm --global --agent pi --skill '*' --yes
    if ($LASTEXITCODE -ne 0) {
        throw "Subtask4LLM skill installation failed (exit $LASTEXITCODE). Retry: npx --yes skills add evgenyigumnov/subtask4llm --global --agent pi --skill '*' --yes"
    }
} finally {
    Pop-Location
}
Write-Host 'Installed. Run pi, then /login. Memory embeddings need OPENROUTER_API_KEY.'
