#!/usr/bin/env bash
# Снимает кадры игры для проверки арта (tools/shoot_run.gd).
#
#   tools/shoot.sh out=/tmp/shots zoom=3 ff=600 frames=3 every=30 hud=0
#
# ⚠️ Запуск НЕ headless и НЕ --write-movie: нужен обычный композит окна,
# ровно тот, что видит игрок. Настройки игрока прячем, как в playtest.sh:
# Settings читает файл в своём _ready, из игры этот момент уже не перехватить.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TIMEOUT_SEC="${SHOOT_TIMEOUT:-300}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	for c in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot" \
		"/usr/local/bin/godot4" "/opt/homebrew/bin/godot4"; do
		if [ -x "$c" ]; then GODOT="$c"; break; fi
	done
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "shoot: не найден godot; задай GODOT=/путь/к/godot" >&2
	exit 2
fi

case "$(uname -s)" in
	Darwin) USER_DIR="$HOME/Library/Application Support/Tidebound" ;;
	*)      USER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/Tidebound" ;;
esac

STASHED=()
stash() {
	[ -f "$USER_DIR/$1" ] || return 0
	mv "$USER_DIR/$1" "$USER_DIR/$1.shoot_bak"
	STASHED+=("$1")
}
restore() {
	for f in ${STASHED[@]+"${STASHED[@]}"}; do
		[ -f "$USER_DIR/$f.shoot_bak" ] || continue
		mv -f "$USER_DIR/$f.shoot_bak" "$USER_DIR/$f"
	done
}
trap 'restore' EXIT INT TERM
stash settings.json
stash save_run.json

"$GODOT" --path "$ROOT" --resolution 1280x720 --position 0,0 \
	-s res://tools/shoot.gd -- "$@" &
PID=$!
( sleep "$TIMEOUT_SEC"; kill -9 "$PID" 2>/dev/null ) &
WATCHDOG=$!
wait "$PID"
CODE=$?
kill "$WATCHDOG" 2>/dev/null
exit "$CODE"
