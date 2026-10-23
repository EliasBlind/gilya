#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/src/main.cpp"
BINDIR="$HOME/.local/bin"
BIN="gilya"

if [ ! -f "$SRC" ]; then
    echo "install.sh: cannot find src/main.cpp (looked at $SRC)" >&2
    exit 1
fi

if command -v g++ >/dev/null 2>&1;       then CXX=g++
elif command -v clang++ >/dev/null 2>&1; then CXX=clang++
else
    echo "install.sh: no C++ compiler found. Install g++ or clang++." >&2
    echo "  Debian/Ubuntu: sudo apt install g++" >&2
    echo "  Fedora:        sudo dnf install gcc-c++" >&2
    echo "  macOS:         xcode-select --install" >&2
    exit 1
fi

mkdir -p "$BINDIR"
echo "Building with $CXX ..."
"$CXX" -std=c++17 -O2 -o "$BINDIR/$BIN" "$SRC"
chmod +x "$BINDIR/$BIN"
echo "Installed -> $BINDIR/$BIN"

apply_block() {
    file="$1"
    block="$2"
    [ -f "$file" ] || : > "$file"
    cp "$file" "$file.gilya.bak" 2>/dev/null || true
    awk '
        /# >>> gilya >>>/ {skip=1; next}
        /# <<< gilya <<</ {skip=0; next}
        skip!=1           {print}
    ' "$file" > "$file.gilya.tmp"
    {
        cat "$file.gilya.tmp"
        printf '%s\n' "$block"
    } > "$file"
    rm -f "$file.gilya.tmp"
    echo "Configured $file  (backup: $file.gilya.bak)"
}

BASH_BLOCK='# >>> gilya >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac
case ":${HISTIGNORE}:" in *":gilya:"*) ;; *) HISTIGNORE="gilya:gilya *${HISTIGNORE:+:$HISTIGNORE}";; esac
# <<< gilya <<<'

ZSH_BLOCK='# >>> gilya >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac
setopt HIST_IGNORE_SPACE
setopt EXTENDED_GLOB
HISTORY_IGNORE='"'"'(gilya|gilya *)'"'"'
# <<< gilya <<<'

[ -n "${BASH_VERSION:-}" ] || command -v bash >/dev/null 2>&1 && apply_block "$HOME/.bashrc" "$BASH_BLOCK"
command -v zsh >/dev/null 2>&1 && apply_block "$HOME/.zshrc" "$ZSH_BLOCK"

echo
echo "Done. Open a new terminal (or 'source' your rc file) to pick up the changes."
echo "Check: command -v gilya   &&   gilya"
