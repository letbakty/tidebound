#!/usr/bin/env bash
# Grep-аудит чистоты sim/. Переносить в tools/audit_sim.sh.
# Запускать перед коммитом любого sim-этапа и обязательно на этапе 19 (п.2).
set -u
FAIL=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/godot" 2>/dev/null || cd "$ROOT" || exit 1

check() {  # check <regex> <описание> [soft] [файл-исключение]
	local hits
	hits=$(grep -rnE "$1" sim/ --include='*.gd' 2>/dev/null \
		| grep -vE '^\s*[^:]+:[0-9]+:\s*#' \
		| { if [ -n "${4:-}" ]; then grep -vE "$4" || true; else cat; fi } || true)
	if [ -n "$hits" ]; then
		if [ "${3:-hard}" = "soft" ]; then
			echo "⚠️  $2"
		else
			echo "❌ $2"
			FAIL=1
		fi
		echo "$hits" | sed 's/^/     /'
	fi
}

echo "=== аудит res://sim/ ==="
# Ловим только БЕЗ точки слева: bare randf() запрещён, а rng.randf() (вызов
# метода SimRNG) законен. Сама обёртка исключена: её объявления func randf()
# и обращения к _rng — и есть тот единственный легальный мост к движку.
check '(^|[^.[:alnum:]_])(randi|randf|randomize|rand_range|randi_range|randf_range)\(' 'глобальный RNG (только через SimRNG)' hard '^sim/sim_rng\.gd:'
check '\bTime\.'                        'Time.* (время — только номер тика)'
check '\bawait\b'                       'await'
check '\bget_tree\(|\bget_node\(|\$'    'доступ к дереву нод'
check '^\s*print\('                     'print (только push_warning/push_error)'
check 'extends\s+Node'                  'Node-наследник'
check '^\s*signal\b'                    'signal (события — только events_out)'
check '\bpreload\('                     'preload сцены'
check '\bOS\.'                          'OS.*'
check 'sort_custom\('                   'sort_custom: проверь тотальность компаратора (research/11 §1.1)' soft
check '\bfmod\('                        'fmod: для отрицательных нужен fposmod' soft

echo "=== проверка типизации ==="
UNTYPED=$(grep -rnE '^\s*(var|const)\s+[a-z_][a-zA-Z0-9_]*\s*=' sim/ --include='*.gd' 2>/dev/null || true)
if [ -n "$UNTYPED" ]; then
	echo "⚠️  возможные нетипизированные объявления:"
	echo "$UNTYPED" | sed 's/^/     /'
fi

if [ $FAIL -eq 0 ]; then echo "✅ sim/ чист"; else echo "sim/ содержит нарушения"; exit 1; fi
