#!/usr/bin/env bash
# Запуск игры целиком, headless, с проходом по экранам (tools/playtest.gd).
#
#   tools/playtest.sh              # заставка -> меню -> забег -> цикл -> меню
#   tools/playtest.sh full         # + весь забег до Итога забега
#   tools/playtest.sh fresh        # ещё и без профиля: путь «профиля нет вовсе»
#
# ⚠️ Зачем сторожевой таймер: часть дефектов UI — это ЗАВИСАНИЕ, а не ошибка
# (`while get_child_count() > MAX: queue_free()` крутится вечно). Упавший
# прогон видно по коду возврата, повисший — только по таймауту.
#
# ⚠️ Зачем прятать user://settings.json ЗДЕСЬ, а не в самом прогоне: Settings
# читает файл в своём _ready, то есть до первого кадра — из игры этот момент
# уже не перехватить. Прогон обязан идти на УМОЛЧАНИЯХ: с чужими флажками
# автопаузы половина проверок теряет смысл.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TIMEOUT_SEC="${PLAYTEST_TIMEOUT:-900}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	for c in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot" \
		"/usr/local/bin/godot4" "/opt/homebrew/bin/godot4"; do
		if [ -x "$c" ]; then GODOT="$c"; break; fi
	done
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "playtest: не найден godot; задай GODOT=/путь/к/godot" >&2
	exit 2
fi

# user:// проекта: application/config/use_custom_user_dir + custom_user_dir_name.
case "$(uname -s)" in
	Darwin) USER_DIR="$HOME/Library/Application Support/Tidebound" ;;
	*)      USER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/Tidebound" ;;
esac

STASHED=()
stash() {
	[ -f "$USER_DIR/$1" ] || return 0
	mv "$USER_DIR/$1" "$USER_DIR/$1.playtest_bak"
	STASHED+=("$1")
}
restore() {
	for f in ${STASHED[@]+"${STASHED[@]}"}; do
		[ -f "$USER_DIR/$f.playtest_bak" ] || continue
		mv -f "$USER_DIR/$f.playtest_bak" "$USER_DIR/$f"
	done
}

LOG="$(mktemp -t tidebound-playtest)"
trap 'restore; rm -f "$LOG"' EXIT INT TERM

stash settings.json          # прогон идёт на умолчаниях, включая автопаузы
stash save_run.json          # «Продолжить» не должно вмешиваться в сценарий
case " $* " in *" fresh "*) stash profile.json ;; esac

"$GODOT" --headless --path "$ROOT" -s res://tools/playtest.gd -- "$@" >"$LOG" 2>&1 &
PID=$!
( sleep "$TIMEOUT_SEC"; kill -9 "$PID" 2>/dev/null ) &
WATCHDOG=$!
wait "$PID"
CODE=$?
# ⚠️ Сначала sleep, потом сама подоболочка: убитая подоболочка оставляет
# sleep сиротой, а он держит открытым stdout. Из-за этого любой конвейер
# (`tools/playtest.sh | tail`) висел ещё столько, сколько оставалось таймауту,
# уже ПОСЛЕ успешного прогона.
pkill -P "$WATCHDOG" 2>/dev/null
kill "$WATCHDOG" 2>/dev/null
cat "$LOG"

if [ "$CODE" -gt 128 ]; then
	echo ""
	echo "❌ игра повисла или упала (сигнал $((CODE - 128))); потолок ${TIMEOUT_SEC}с"
	exit 1
fi

# Тот же второй рубеж, что и в run_tests.sh: GDScript не видит ошибок движка.
ERR_RE='^(SCRIPT ERROR|SCRIPT FAILED|ERROR):'
ENGINE_ERRORS=$(grep -cE "$ERR_RE" "$LOG" || true)
if [ "${ENGINE_ERRORS:-0}" -gt 0 ]; then
	echo ""
	echo "❌ ошибок движка за прогон: $ENGINE_ERRORS"
	grep -E "$ERR_RE" "$LOG" | sort | uniq -c | sort -rn | head -20
	exit 1
fi

if [ "$CODE" -ne 0 ]; then
	echo "❌ прогон провален (код $CODE)"
	exit "$CODE"
fi
echo "✅ игра запускается и проходится: ошибок движка нет"
