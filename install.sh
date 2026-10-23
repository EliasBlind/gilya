#!/bin/sh
# install.sh — build & install `gilya`, keep it out of shell history, and scrub
# any gilya commands already recorded. Covers bash, zsh and fish on Linux/macOS.
# No root required (installs into ~/.local/bin).
#
# Run from the repo root (the folder that contains src/main.cpp):
#   sh install.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/src/main.cpp"
BINDIR="$HOME/.local/bin"
BIN="gilya"

[ -f "$SRC" ] || { echo "install.sh: cannot find src/main.cpp (looked at $SRC)" >&2; exit 1; }

# --- 1. compiler ----------------------------------------------------------
if command -v g++ >/dev/null 2>&1;       then CXX=g++
elif command -v clang++ >/dev/null 2>&1; then CXX=clang++
else
    echo "install.sh: no C++ compiler found. Install g++ or clang++." >&2
    echo "  Debian/Ubuntu: sudo apt install g++      macOS: xcode-select --install" >&2
    exit 1
fi

# --- 2. build & install ---------------------------------------------------
mkdir -p "$BINDIR"
echo "Building with $CXX ..."
"$CXX" -std=c++17 -O2 -o "$BINDIR/$BIN" "$SRC"
chmod +x "$BINDIR/$BIN"
echo "Installed -> $BINDIR/$BIN"

# --- helpers --------------------------------------------------------------
# Replace a marked block in a file (idempotent), keeping everything else.
apply_block() { # file block
    f="$1"; b="$2"
    [ -f "$f" ] || : > "$f"
    cp "$f" "$f.gilya.bak" 2>/dev/null || true
    awk '/# >>> gilya >>>/{s=1;next} /# <<< gilya <<</{s=0;next} s!=1{print}' "$f" > "$f.gilya.tmp"
    { cat "$f.gilya.tmp"; printf '%s\n' "$b"; } > "$f"
    rm -f "$f.gilya.tmp"
    echo "  configured $f  (backup $f.gilya.bak)"
}

# Remove already-recorded gilya lines from a history file.
scrub_file() { # file regex
    f="$1"; re="$2"
    [ -f "$f" ] || return 0
    cp "$f" "$f.gilya.bak" 2>/dev/null || true
    grep -v -E "$re" "$f" > "$f.gilya.tmp" 2>/dev/null || true
    mv "$f.gilya.tmp" "$f"
    echo "  scrubbed $f  (backup $f.gilya.bak)"
}

# --- 3. shell blocks ------------------------------------------------------
# bash: HISTIGNORE excludes gilya from the in-session list AND the file.
BASH_BLOCK='# >>> gilya >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac
case ":${HISTIGNORE}:" in *":gilya:"*) ;; *) HISTIGNORE="gilya:gilya *${HISTIGNORE:+:$HISTIGNORE}";; esac
# <<< gilya <<<'

# zsh: HISTORY_IGNORE only filters the FILE, so the current session would still
# recall gilya with the up-arrow. A zshaddhistory hook returning non-zero keeps
# the line out of the internal history entirely.
ZSH_BLOCK='# >>> gilya >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac
setopt HIST_IGNORE_SPACE
autoload -Uz add-zsh-hook
_gilya_nohist() { emulate -L zsh; [[ ${${1%%$'"'"'\n'"'"'}%%[[:space:]]*} != gilya ]] }
add-zsh-hook zshaddhistory _gilya_nohist
# <<< gilya <<<'

# fish: no HISTIGNORE; a fish_postexec event deletes the exact line afterwards.
FISH_PATH_BLOCK='# >>> gilya >>>
if not contains $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end
# <<< gilya <<<'

# --- 4. apply per shell ---------------------------------------------------
if command -v bash >/dev/null 2>&1 || [ -f "$HOME/.bashrc" ]; then
    echo "bash:"
    apply_block "$HOME/.bashrc" "$BASH_BLOCK"
    scrub_file "$HOME/.bash_history" '^gilya([[:space:]].*)?$'
fi

if command -v zsh >/dev/null 2>&1 || [ -f "$HOME/.zshrc" ]; then
    echo "zsh:"
    apply_block "$HOME/.zshrc" "$ZSH_BLOCK"
    scrub_file "${HISTFILE:-$HOME/.zsh_history}" '^(: [0-9]+:[0-9]+;)?gilya([[:space:]].*)?$'
fi

if command -v fish >/dev/null 2>&1 || [ -d "$HOME/.config/fish" ]; then
    echo "fish:"
    mkdir -p "$HOME/.config/fish/conf.d"
    apply_block "$HOME/.config/fish/config.fish" "$FISH_PATH_BLOCK"
    cat > "$HOME/.config/fish/conf.d/gilya.fish" <<'GILYA_FISH'
# gilya: keep gilya commands out of fish history
function _gilya_no_history --on-event fish_postexec
    if string match -qr '^\s*gilya(\s|$)' -- "$argv"
        builtin history delete --exact --case-sensitive -- "$argv" 2>/dev/null
    end
end
GILYA_FISH
    echo "  configured $HOME/.config/fish/conf.d/gilya.fish"
    if command -v fish >/dev/null 2>&1; then
        fish -c 'for c in (builtin history search --prefix "gilya"); builtin history delete --exact --case-sensitive -- $c; end' 2>/dev/null || true
        echo "  scrubbed fish history"
    fi
fi

echo
echo "Done. From now on gilya is never recorded in bash / zsh / fish history."
echo "Already-open terminals still hold old history in memory — in each of them run:"
echo "    exec \$SHELL"
echo "or just close and reopen the terminal."
