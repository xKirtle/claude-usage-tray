#!/usr/bin/env bash
# Install by symlinking this checkout into place, so edits here apply directly.
#   ./install.sh            install + enable the user service
#   ./install.sh --uninstall
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$HOME/.local/bin/claude-usage-tray"
panel="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/claude-usage"
unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/claude-usage-tray.service"

# Move a non-symlink out of the way instead of overwriting it.
backup() {
    if [[ -e "$1" && ! -L "$1" ]]; then
        mv "$1" "$1.bak.$(date +%s)"
        echo "backed up $1"
    fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
    systemctl --user disable --now claude-usage-tray.service 2>/dev/null || true
    qs -c claude-usage kill 2>/dev/null || true
    rm -f "$bin" "$panel" "$unit"
    systemctl --user daemon-reload
    echo "uninstalled (cache left in ~/.cache/claude-usage)"
    exit 0
fi

mkdir -p "$(dirname "$bin")" "$(dirname "$panel")" "$(dirname "$unit")"
for target in "$bin" "$panel" "$unit"; do
    backup "$target"
done
ln -sfn "$repo/claude-usage-tray" "$bin"
ln -sfn "$repo/panel" "$panel"
ln -sfn "$repo/systemd/claude-usage-tray.service" "$unit"

systemctl --user daemon-reload
systemctl --user enable claude-usage-tray.service
systemctl --user restart claude-usage-tray.service
qs -c claude-usage kill 2>/dev/null || true  # panel restarts on next click
echo "installed; the icon should appear in your tray"
