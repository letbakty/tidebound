extends SceneTree
## Лист агента из отобранного арта (prompts/ART-integration §2 п.4).
##
##   godot --headless -s res://tools/gen_agent.gd
##   godot --headless --import --quit
##
## Сборка, а не «положить PNG руками»: у нас ПЯТЬ листов по 8 кадров плюс
## статичный дизайн, а game/agent_view.gd умеет читать один лист сеткой.
## Ряд = состояние, столбец = кадр; порядок рядов — контракт с AgentView.ROWS,
## его сторожит tests/test_visual.gd.
##
## ⚠️ Ряд ожидания заполнен ОДНИМ кадром восемь раз намеренно: так любой номер
## кадра валиден в любом ряду, и ошибка в расчёте кадра не может показать
## прозрачную дыру вместо агента.

const Art: GDScript = preload("res://tools/art_lib.gd")

const CELL: Vector2i = Vector2i(16, 24)
const COLS: int = 8
const OUT_PNG: String = "res://assets/sprites/agent.png"
const OUT_DEAD: String = "res://assets/sprites/agent_dead.png"

## Порядок рядов = AgentView.Row. Первый файл ряда — источник кадров.
const ROWS: Array[Dictionary] = [
	{"name": "idle", "src": "agent_design_v3_03_pick.png", "single": true},
	{"name": "walk", "src": "agent_walk_v2_01_pick.png"},
	{"name": "carry", "src": "agent_carry_v1_01_pick.png"},
	{"name": "work", "src": "agent_work_v1_01_pick.png"},
	{"name": "drown", "src": "agent_drown_v1_01_pick.png"},
	{"name": "panic", "src": "agent_panic_v1_01_pick.png"},
]

## Лежащий агент повёрнут: 24×16, а не 16×24 — в клетку листа он не влезает и
## живёт отдельным файлом.
const DEAD_SRC: String = "agent_dead_v1_03_pick.png"

func _initialize() -> void:
	var edge: Color = Art.darkest(Art.palette())
	var sheet: Image = Image.create(CELL.x * COLS, CELL.y * ROWS.size(), false,
		Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for r: int in ROWS.size():
		var row: Dictionary = ROWS[r]
		var src: String = str(row["src"])
		if bool(row.get("single", false)):
			var one: Image = Art.load_pick(src, CELL.x, CELL.y)
			if one == null:
				continue
			one = Art.outline(one, edge)
			for c: int in COLS:
				sheet.blit_rect(one, Rect2i(Vector2i.ZERO, CELL),
					Vector2i(c * CELL.x, r * CELL.y))
			print("ряд %d %-6s ← %s (один кадр ×%d)" % [r, str(row["name"]), src, COLS])
			continue
		var strip: Image = Art.load_pick(src, CELL.x * 4, CELL.y * 2)
		if strip == null:
			continue
		# Лист 64×48 — это 4 кадра в ряд и два ряда, то есть цикл из восьми
		# кадров подряд, а не два разных состояния.
		var frames: Array[Image] = Art.frames(strip, CELL)
		for c2: int in mini(COLS, frames.size()):
			sheet.blit_rect(Art.outline(frames[c2], edge),
				Rect2i(Vector2i.ZERO, CELL), Vector2i(c2 * CELL.x, r * CELL.y))
		print("ряд %d %-6s ← %s (%d кадров)" % [r, str(row["name"]), src, frames.size()])
	if not Art.save(sheet, OUT_PNG):
		quit(2)
		return
	var dead: Image = Art.load_pick(DEAD_SRC, 24, 16)
	if dead != null:
		Art.save(Art.outline(dead, edge), OUT_DEAD)
	quit(1 if Art.fails > 0 else 0)
