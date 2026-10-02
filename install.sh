#!/bin/sh
# install.sh - put the vis kit in place on a box, fast. Idempotent.
#
#   curl -fsSL https://raw.githubusercontent.com/jeffctl/vis-kit/main/install.sh | sh
#                                         # on a box with nothing: fetches the kit, installs vis, places the config
#   cd vis-kit && ./install.sh            # from a checkout: install vis if missing, copy the config
#   ./install.sh --link                   # symlink instead of copy (for a dotfiles clone)
#   ./install.sh --no-install             # just place the config, never touch the package manager
#   ./install.sh --dir /some/where        # place it somewhere other than ~/.config/vis
#
# Targets Kali/Debian/Ubuntu (apt), Fedora (dnf), Alpine/iSH (apk), Termux (pkg), macOS (brew).
# KIT_URL overrides where a standalone run fetches the kit from.
set -eu

LINK=0
DO_INSTALL=1
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/vis"

while [ $# -gt 0 ]; do
	case "$1" in
	--link) LINK=1 ;;
	--no-install) DO_INSTALL=0 ;;
	--dir) shift; DEST="$1" ;;
	-h|--help) sed -n '2,12p' "$0"; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

say() { printf '%s\n' "$*"; }

# root needs no sudo, and a bare CTF box may not even have it
if [ "$(id -u)" -eq 0 ]; then SUDO=""; elif command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else SUDO=""; fi

# the kit is the folder this script lives in; run standalone (curl | sh), fetch it
SRC=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ ! -f "$SRC/visrc.lua" ]; then
	KIT_URL="${KIT_URL:-https://github.com/jeffctl/vis-kit/archive/refs/heads/main.tar.gz}"
	TMP=$(mktemp -d 2>/dev/null || mktemp -d -t viskit)
	say "fetching the kit from $KIT_URL"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$KIT_URL" | tar xz -C "$TMP"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$KIT_URL" | tar xz -C "$TMP"
	elif command -v git >/dev/null 2>&1; then
		git clone -q --depth 1 https://github.com/jeffctl/vis-kit "$TMP/vis-kit"
	else
		say "need curl, wget or git to fetch the kit" >&2; exit 1
	fi
	SRC=$(dirname "$(find "$TMP" -name visrc.lua | head -1)")
	[ -f "$SRC/visrc.lua" ] || { say "could not fetch the kit" >&2; exit 1; }
fi

# ---- 1. make sure vis is present ----------------------------------------
install_vis() {
	if command -v vis >/dev/null 2>&1; then return 0; fi
	[ "$DO_INSTALL" -eq 1 ] || { say "vis not found and --no-install given; install it yourself"; return 1; }
	say "vis not found; installing it..."
	if command -v apt-get >/dev/null 2>&1; then
		$SUDO apt-get update -qq && $SUDO apt-get install -y vis
	elif command -v apk >/dev/null 2>&1; then
		$SUDO apk add vis
	elif command -v dnf >/dev/null 2>&1; then
		# Fedora ships vis; RHEL/Rocky/Alma do not (need a COPR or source)
		if ! $SUDO dnf install -y vis 2>/dev/null; then
			say "dnf has no 'vis' (RHEL/Rocky/Alma base lacks it). Options:"
			say "  $SUDO dnf copr enable madchem/vis-editor && $SUDO dnf install vis"
			say "  or build from source, or use the static single binary (see README)."
			return 1
		fi
	elif command -v pkg >/dev/null 2>&1; then
		pkg install -y vis
	elif command -v brew >/dev/null 2>&1; then
		brew install vis
	else
		say "no known package manager (apt/dnf/apk/pkg/brew); build vis from source:"
		say "  git clone https://github.com/martanne/vis && cd vis && ./configure && make && sudo make install"
		return 1
	fi
}
install_vis || say "WARNING: vis is not installed; the config is still placed below."

# ---- 2. place the config ------------------------------------------------
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
	BAK="$DEST.bak-$(date +%Y%m%d%H%M%S)"
	say "moving existing $DEST -> $BAK"
	mv "$DEST" "$BAK"
fi
mkdir -p "$(dirname "$DEST")"

if [ "$LINK" -eq 1 ]; then
	ln -s "$SRC" "$DEST"
	say "linked $DEST -> $SRC"
else
	mkdir -p "$DEST"
	# copy the config files only (not .git, not this script's backups)
	for item in visrc.lua kit themes lexers templates install.sh README.md LICENSE; do
		[ -e "$SRC/$item" ] && cp -R "$SRC/$item" "$DEST/"
	done
	say "copied the kit into $DEST"
fi

# ---- 3. verify ----------------------------------------------------------
FAIL=0
if command -v vis >/dev/null 2>&1; then
	V=$(vis -v 2>&1 | head -1)
	say "vis: $V"
	case "$V" in
	*+lua*) : ;;
	*) say "FAIL: this vis was built WITHOUT Lua; the kit cannot run"; FAIL=1 ;;
	esac
else
	say "FAIL: vis is not on PATH"; FAIL=1
fi
command -v vis-menu    >/dev/null 2>&1 || say "note: vis-menu not found - the fuzzy pickers fall back to the panel (Space ? still works)"
command -v vis-clipboard >/dev/null 2>&1 || say "note: vis-clipboard not found - the system-clipboard keys ("'"'"+ / Space fp) are off"
[ -f "$DEST/visrc.lua" ] || { say "FAIL: $DEST/visrc.lua is missing"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then
	say ""
	say "PASS. Run:  vis        (opens your day)"
	say "            vis notes.org"
	say "Org files live in ~/org (override with ORG_DIR). Space ? finds any key."
else
	say ""
	say "Something is off above - fix the FAIL line(s) and re-run."
	exit 1
fi
