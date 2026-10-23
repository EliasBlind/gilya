#!/bin/sh
set -eu

KEEP_DATA=0
for a in "$@"; do
    case "$a" in
    --keep-data) KEEP_DATA=1 ;;
    -h | --help)
        echo "usage: sh uninstall.sh [--keep-data]"
        exit 0
        ;;
    *)
        echo "uninstall.sh: unknown option: $a" >&2
        exit 2
        ;;
    esac
done

BIN="$HOME/.local/bin/gilya"
FISHCFG="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/gilya"

strip_block() { # file
    f="$1"
    [ -f "$f" ] || return 0
    grep -q '# >>> gilya >>>' "$f" 2>/dev/null || return 0
    [ -f "$f.gilya.bak" ] || cp "$f" "$f.gilya.bak" 2>/dev/null || true
    awk '/# >>> gilya >>>/{s=1;next} /# <<< gilya <<</{s=0;next} s!=1{print}' "$f" > "$f.gilya.tmp"
    mv "$f.gilya.tmp" "$f"
    echo "  cleaned $f"
}

echo "Removing gilya ..."

if [ -e "$BIN" ]; then
    rm -f "$BIN"
    echo "  removed $BIN"
fi

strip_block "$HOME/.bashrc"
strip_block "$HOME/.zshrc"
strip_block "$FISHCFG/config.fish"

if [ -e "$FISHCFG/conf.d/gilya.fish" ]; then
    rm -f "$FISHCFG/conf.d/gilya.fish"
    echo "  removed $FISHCFG/conf.d/gilya.fish"
fi

if [ "$KEEP_DATA" -eq 1 ]; then
    [ -d "$DATA" ] && echo "  kept remembered files in $DATA" || true
elif [ -d "$DATA" ]; then
    rm -rf "$DATA"
    echo "  removed data $DATA"
fi

echo
echo "Done. Open a new terminal (or run 'exec \$SHELL') so the shell drops the"
echo "PATH and history settings from the current session."
echo "History files were cleaned of gilya at install time; *.gilya.bak backups remain."
