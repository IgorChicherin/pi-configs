#!/usr/bin/env bash
set -euo pipefail

for command in pi stow npx; do
    command -v "$command" >/dev/null || { printf 'Required command missing: %s\n' "$command" >&2; exit 1; }
done
if [[ -n "${PI_CODING_AGENT_DIR:-}" ]]; then
    printf 'Unset PI_CODING_AGENT_DIR; this installer targets ~/.pi/agent.\n' >&2
    exit 1
fi

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Keep runtime directories real, not symlinked into the repository.
stow --simulate --no-folding --dir="$root" --target="$HOME" pi
stow --no-folding --dir="$root" --target="$HOME" pi

# Reconcile the unpinned packages declared in settings.json.
(
    cd -- "$HOME"
    pi update --extensions
    npx --yes skills add mattpocock/skills --global --agent pi --skill '*' --yes
)
printf 'Installed. Run pi, then /login. Memory embeddings need OPENROUTER_API_KEY.\n'
