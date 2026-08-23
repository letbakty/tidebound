#!/usr/bin/env bash
# Ремап переживает перезапуск игры — проверка в ДВА процесса.
#
#   tools/remapcheck.sh
#
# Первый процесс назначает «Отзыв» на R через настоящую вкладку настроек и
# пишет user://settings.json. Второй запускается с нуля и проверяет, что
# клавиша применилась, кнопка геймпада на том же действии жива, а полоса
# подсказок показывает новую клавишу. Одним процессом это не проверить: сломан
# был именно стык «файл -> Settings._ready -> InputMap».
#
# Свой settings.json на время прогона убирается в .bak и возвращается в конце.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	for c in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot" \
		"/usr/local/bin/godot4" "/opt/homebrew/bin/godot4"; do
		if [ -x "$c" ]; then GODOT="$c"; break; fi
	done
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "remapcheck: не найден godot; задай GODOT=/путь/к/godot" >&2
	exit 2
fi

case "$(uname -s)" in
	Darwin) USER_DIR="$HOME/Library/Application Support/Tidebound" ;;
	*)      USER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/Tidebound" ;;
esac
STASHED=0
if [ -f "$USER_DIR/settings.json" ]; then
	mv "$USER_DIR/settings.json" "$USER_DIR/settings.json.remapcheck_bak"
	STASHED=1
fi
restore() {
	[ "$STASHED" = "1" ] || return 0
	mv -f "$USER_DIR/settings.json.remapcheck_bak" "$USER_DIR/settings.json"
}
trap restore EXIT INT TERM

LOG="$(mktemp -t tidebound-remapcheck)"
CODE=0
for phase in set verify; do
	echo "=== процесс: $phase"
	"$GODOT" --headless --path "$ROOT" -s res://tools/remapcheck.gd -- "$phase" \
		>"$LOG" 2>&1 || CODE=1
	grep -E '^(   |>|REMAPCHECK)' "$LOG" || true
	ERRORS=$(grep -cE '^(SCRIPT ERROR|SCRIPT FAILED|ERROR):' "$LOG" || true)
	if [ "${ERRORS:-0}" -gt 0 ]; then
		echo "❌ ошибок движка в фазе $phase: $ERRORS"
		grep -E '^(SCRIPT ERROR|SCRIPT FAILED|ERROR):' "$LOG" | head -5
		CODE=1
	fi
done
rm -f "$LOG"
if [ "$CODE" -ne 0 ]; then
	echo "❌ ремап перезапуск не пережил"
	exit "$CODE"
fi
echo "✅ ремап пережил перезапуск игры"
