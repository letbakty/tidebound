#!/usr/bin/env bash
# Раннер тестов TIDEBOUND. Единственный поддерживаемый способ прогнать сьюты.
#
#   tools/run_tests.sh                 # весь прогон
#   tools/run_tests.sh res://tests/test_production.gd   # один сьют
#
# ⚠️ Почему обёртка, а не просто `godot -s res://tests/run_all.gd`:
# GDScript не видит рантайм-ошибок движка. Раннер внутри игры проверяет только
# свои check(), поэтому 365 `SCRIPT ERROR` за прогон жили в проекте при
# полностью зелёном отчёте (docs/BUG-salt-chain.md, «Урок для этапа 19»).
# Здесь прогон валится и по провалу check(), и по любой ошибке движка.
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
	echo "run_tests: не найден godot; задай GODOT=/путь/к/godot" >&2
	exit 2
fi

SUITE="${1:-res://tests/run_all.gd}"
LOG="$(mktemp -t tidebound-tests)"
trap 'rm -f "$LOG"' EXIT

"$GODOT" --headless --path "$ROOT" -s "$SUITE" 2>&1 | tee "$LOG"
CODE=${PIPESTATUS[0]}

# Ошибки движка. USER ERROR намеренно НЕ ловим: это push_error, которым
# пользуются и сам код (мягкий отказ на битых данных), и тесты, проверяющие
# этот отказ, и TestCtx.check — провал check и так виден по коду возврата.
# SCRIPT ERROR / SCRIPT FAILED / ERROR — рантайм движка, всегда дефект.
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
echo "✅ прогон чист: тесты зелёные, ошибок движка нет"
