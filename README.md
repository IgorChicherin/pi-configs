# Pi configs

Portable snapshot of personal [Pi](https://pi.dev) harness configuration.
Linux/macOS use GNU Stow; Windows copies the same files. No credentials, sessions,
memory data, or installed dependencies are included. Installers download external
Matt Pocock skills separately; their contents are not stored in this repository.

## Contents

```text
pi/.pi/agent/
  settings.json        # Unpinned plugin sources; no device/changelog state
  models.json          # Ollama models and context metadata
  APPEND_SYSTEM.md     # Caveman Ultra instruction
  mcp.json             # Context7 MCP endpoint
  active-memory.json   # OpenRouter embedding provider; environment variable only
  lsp.json             # Go, basedpyright, C/C++, YAML, JSON servers
install.sh             # Linux/macOS: Stow + plugin/skill installation
install.ps1            # Windows: copy + plugin/skill installation
```

## Installed plugins

Versions below describe the source machine at snapshot time, not install pins.
Installers reconcile the unpinned `packages` list in `settings.json` using
`pi update --extensions`. New machines may receive different versions.

| Plugin | Source | Observed version/ref |
| --- | --- | --- |
| Billion Context | `npm:billion-context` | Not recorded; added to restore configuration |
| Web search | `npm:pi-web-search` | `1.7.0` |
| LSP | `npm:pi-lsp` | `0.1.7` |
| Ponytail | `git:github.com/DietrichGebert/ponytail` | `96608e078b2d5ea607c5c3b8b5a54d1c1fba6846` |
| Active memory | `npm:pi-active-memory` | `1.9.0` |
| Ollama native provider | `npm:pi-ollama` | Unpinned; added to restore configuration |
| Caveman | `git:github.com/v2nic/pi-caveman` | `2480692ffabddc3d1efec8eb822e664ff7e0e5ef` |

Package-bundled skills are installed with their plugins. Review third-party
plugins before installing: extensions execute code, and installation requires
network access.

## External skills

Both installers also install all available skills from
[Matt Pocock's skills](https://github.com/mattpocock/skills) globally for Pi:

```bash
npx --yes skills add mattpocock/skills --global --agent pi --skill '*' --yes
```

The Skills CLI installs them under `~/.agents/skills/`, which Pi discovers
automatically. No skill files are vendored here. The CLI and skill source are
unpinned; future installs may include new or changed skills. This noninteractive
command may replace matching installed skills, so back up local customizations
first. Other external skill repositories are not restored.

## Prerequisites

- Close Pi before restoring config.
- Install Node.js **22.19+**, npm (including `npx`), Git, and Pi. One supported Pi install method:
  `npm install -g --ignore-scripts @earendil-works/pi-coding-agent`.
- Linux/macOS: install GNU Stow through your package manager, for example
  `brew install stow` or `sudo apt install stow`.
- Windows: use PowerShell with `pi` available on `PATH`.
- Leave `PI_CODING_AGENT_DIR` unset: these installers target the default home layout.
- Back up existing config and move conflicting destination files aside. Installers
  refuse Pi config conflicts; they do not merge existing settings or replace credentials.
  Existing runtime directories and unrelated files can remain.

## Linux / macOS

From this repository:

```bash
bash ./install.sh
```

The script checks conflicts with Stow's dry run, then runs:

```bash
stow --no-folding --dir="$PWD" --target="$HOME" pi
pi update --extensions
npm install --prefix "$HOME/.pi/agent/lsp-servers" --no-save --package-lock=false --ignore-scripts basedpyright yaml-language-server vscode-langservers-extracted
npx --yes skills add mattpocock/skills --global --agent pi --skill '*' --yes
```

`--no-folding` links individual config files, not whole directories. Pi's runtime
files therefore stay under your actual home, not inside this repository. Keep the
repository in place while linked. Pi edits to linked configs can change tracked
files; review `git diff` before committing, especially for secrets or device state.

To remove only the links, from the repository:

```bash
stow --delete --no-folding --dir="$PWD" --target="$HOME" pi
```

This does not uninstall plugins or external skills, or delete runtime data.

## Windows

`pi-lsp` 0.1.7 looks for `PI_AGENT_DIR` or `HOME`, not Windows `USERPROFILE`.
Set its agent directory once, then restart your terminal and Pi so they inherit it:

```powershell
[Environment]::SetEnvironmentVariable('PI_AGENT_DIR', (Join-Path $HOME '.pi/agent'), 'User')
```

From this repository in the new PowerShell terminal:

```powershell
.\install.ps1
```

The script checks LSP config discovery and all six destination files before copying them to
`$HOME\.pi\agent`, then installs the plugins and external skills. No administrator access or Stow is
needed. If local execution policy blocks the script, review it first, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Manual alternative: copy the **contents** of `pi/`, including its hidden `.pi`
directory, into your user profile after backing up conflicting files. Do not copy
the outer `pi` directory itself. Then run `pi update --extensions` and the external
skills command above from your home.
Windows copies are independent: later edits do not update this repository.
Rerunning `install.ps1` refuses existing config files, even identical ones; to
retry plugin installation alone, run `pi update --extensions`.

## After restoring

1. Start `pi` and use `/login` to authenticate separately.
2. For Ollama, the restored `models.json` lists your models; `pi-ollama` uses Ollama's native API. Run `/ollama-context` in Pi to set its context length; this setting is persisted by the plugin. Configure `OLLAMA_HOST` if your xOllama server is not at the default `http://localhost:11434`.
3. For memory embeddings, set `OPENROUTER_API_KEY` outside this repository. The
   configured model is `perplexity/pplx-embed-v1-0.6b`; this is a paid OpenRouter
   embedding model and requires account credit. Memory contents are not restored.
   Existing installations switching models must approve re-embedding at Pi startup;
   declining or a failed migration disables Active Memory for that session.
4. Configure web-search provider credentials separately if required by your
   chosen provider. Context7 uses its public MCP URL; no token is included.
5. Use `pi list` to inspect configured plugins.

If plugin installation fails, deployed configs remain in place. Fix the network
or prerequisite issue, then run `pi update --extensions` from your home directory.
If external skill installation fails, retry the `npx` command above. Existing
configs and plugins remain installed. No automatic rollback or synchronization
is performed.

## Language servers

`pi-lsp` adds diagnostics after edits and model tools for hover, definitions,
references, and symbols. Both installers deploy `lsp.json` and install unpinned
basedpyright, YAML, and JSON server packages under `~/.pi/agent/lsp-servers`.
Node launches their entry points directly, avoiding Windows `.cmd` shims.
The extra `lsp-server` argument supplies the script-name slot expected by their
CLI parsers. YAML uses dynamic import because its entry point is ESM.

Install Go and LLVM/clangd separately, then ensure `gopls` and `clangd` are on
Pi's `PATH`:

```bash
go install golang.org/x/tools/gopls@latest
```

Go installs `gopls` in `GOBIN` or `$(go env GOPATH)/bin`; add that directory to
`PATH`. Install clangd with your OS package manager (for example
`sudo apt install clangd`, `brew install llvm`, or `scoop install llvm`).
Ensure the LLVM `bin` directory is on `PATH` if your package manager does not add it.

| Files | Server | Notes |
| --- | --- | --- |
| `.go` | gopls | Requires `go.mod` or `go.work` |
| `.py`, `.pyi` | basedpyright | Requires Python/interpreter dependencies for accurate analysis |
| C/C++ sources and headers | clangd | Generate `compile_commands.json` for accurate include paths and flags |
| `.yaml`, `.yml` | yaml-language-server | Supports YAML schemas |
| `.json`, `.jsonc` | vscode-json-language-server | JSON and JSON-with-comments |

Except Go, servers use Pi's working directory as workspace root, including
standalone files. Start Pi at the project root. For CMake projects, generate
`compile_commands.json` with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`; if it lives
under `build/`, expose it at the project root or configure clangd through `.clangd`.
Headers ending in `.h` default to C; override the mapping in project `.pi/lsp.json`
for C++-only projects. No automatic schema associations or custom compiler flags
are imposed.

For an existing Pi setup, **do not rerun the conflict-rejecting installer**.
With Pi closed, back up any existing `~/.pi/agent/lsp.json`, copy
`pi/.pi/agent/lsp.json` there, then run:

```bash
pi install npm:pi-lsp
npm install --prefix "$HOME/.pi/agent/lsp-servers" --no-save --package-lock=false --ignore-scripts basedpyright yaml-language-server vscode-langservers-extracted
```

The same commands work in PowerShell; also set `PI_AGENT_DIR` as shown in the
Windows section, including for manual/existing installations. Restart Pi after adding servers or changing
`PATH`. Ask Pi to inspect a definition or hover to verify server startup;
`lsp_diagnostics` alone only reads cached diagnostics. Project `.pi/lsp.json`
overrides matching server IDs and requires trust. Global config can launch
programs without a project trust prompt; review changes before deploying.

If server installation fails, rerun the `npm install` command above; deployed
configs remain. Native Go/LLVM dependencies and language environments are not
installed or upgraded by these scripts.

## Updating the snapshot

Edit tracked files directly, or manually copy reviewed, sanitized config back
from Windows. Keep `settings.json` limited to portable preferences and plugin
sources; do not copy device IDs, changelog history, API keys, or auth files.
The Stow package ignores all agent files except the six listed above, but Git
ignore rules do not detect secrets pasted into tracked files.

Plugin sources live only in `settings.json`; update the inventory table when
changing them. External Matt Pocock skills are downloaded by the install scripts,
not snapshotted. There is no automatic snapshot job.

## Checks

With Python 3, Bash, and GNU Stow installed:

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
```

Windows installer checks, from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-install.ps1
```

Tests use temporary homes and fake `pi`/`npx` commands; they do not install plugins
or skills, contact providers, or modify your live Pi configuration. Run the
PowerShell test in a fresh process as shown; it temporarily replaces that process's
home variable and `pi`/`npx` commands.
