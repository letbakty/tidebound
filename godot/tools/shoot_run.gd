extends RefCounted
## Съёмка кадров НАСТОЯЩЕЙ игры для проверки арта (prompts/ART-integration §3).
##
## Зачем: половина сгенерированного арта разваливается именно в игре при
## зуме ×3 — в просмотрщике этого не видно вообще. Смотреть надо на
## композит целиком: мир идёт через SubViewport 640x360 со stretch_shrink 2,
## то есть ×3 — это зум камеры 1.5 внутри вьюпорта. Дробность видна только
## на финальном кадре окна, а не на текстуре тайла.
##
##   tools/shoot.sh out=<dir> zoom=3 ff=600 frames=3 every=30 hud=0 cell=x,y
##
## ⚠️ Запуск НЕ headless: без рендера снимать нечего.

const MAIN_SCENE: String = "res://game/main.tscn"
## Потолок ожидания шага, кадров.
const WAIT_FRAMES: int = 600
## Размер куска промотки: каждый debug_fast_forward заканчивается
## rebroadcast_state(), и именно он, а не тики, стоит времени.
const FF_CHUNK: int = 250

var _tree: SceneTree = null
var _main: Control = null
var _router: ScreenRouter = null

var _out_dir: String = "user://shots"
var _zoom: int = 3
var _ff: int = 0
var _frames: int = 1
var _every: int = 30
var _hud: bool = false
var _cell: Vector2i = Vector2i(-1, -1)
var _seed: int = 20260822
var _speed: int = 1
## Масштаб контента окна. -1 = как у игрока (ui_scale × DPI). Ставить 1.0
## нужно, чтобы увидеть ЧИСТЫЙ зум ×3: на HiDPI игрок видит ×3 × DPI-масштаб,
## и пиксель тайла разъезжается на 2–3 экранных.
var _cscale: float = -1.0


func start(tree: SceneTree) -> void:
	_tree = tree
	_parse_args()
	_drive()

func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"out": _out_dir = kv[1]
			"zoom": _zoom = int(kv[1])
			"ff": _ff = int(kv[1])
			"frames": _frames = maxi(1, int(kv[1]))
			"every": _every = maxi(1, int(kv[1]))
			"hud": _hud = kv[1] != "0"
			"seed": _seed = int(kv[1])
			"speed": _speed = int(kv[1])
			"cscale": _cscale = float(kv[1])

			"cell":
				var xy: PackedStringArray = kv[1].split(",")
				if xy.size() == 2:
					_cell = Vector2i(int(xy[0]), int(xy[1]))

func _drive() -> void:
	await _tree.process_frame
	_tree.change_scene_to_file(MAIN_SCENE)
	await _tree.process_frame
	await _tree.process_frame
	_main = _tree.current_scene as Control
	if _main == null:
		_die("сцена игры не загрузилась")
		return
	_router = _main.get("router") as ScreenRouter
	if _router == null:
		_die("Main без router — сцена собралась не до конца")
		return

	if not await _wait(func() -> bool: return _router.current != ScreenRouter.Screen.BOOT):
		_die("заставка не ушла")
		return
	if _router.current == ScreenRouter.Screen.FIRST_LAUNCH:
		var first: FirstLaunch = _router.screen_node(
			ScreenRouter.Screen.FIRST_LAUNCH) as FirstLaunch
		first.done.emit(false)
		await _tree.process_frame

	Settings.world_zoom = _zoom
	var menu: MainMenu = _router.screen_node(ScreenRouter.Screen.MAIN_MENU) as MainMenu
	if menu == null:
		_die("главное меню не зарегистрировано")
		return
	menu.new_run_requested.emit(_seed)
	await _tree.process_frame
	if not await _wait(func() -> bool: return Game.world != null):
		_die("мир не создался")
		return
	# Стартовый драфт держит автопаузу: без выбора карты забег не пойдёт.
	if await _wait(func() -> bool: return _router.modal == ScreenRouter.Modal.DRAFT):
		var draft: DraftPanel = _router.modal_node(ScreenRouter.Modal.DRAFT) as DraftPanel
		var ids: Array[String] = Game.world.run_state.draft.duplicate()
		if not ids.is_empty():
			draft.card_confirmed.emit(ids[0])
		await _tree.process_frame

	if _ff > 0:
		var left: int = _ff
		while left > 0:
			Game.debug_fast_forward(mini(FF_CHUNK, left))
			left -= FF_CHUNK
			await _tree.process_frame

	var world: WorldView = _main.get("world_view") as WorldView
	world.camera.set_zoom_step(_zoom)
	if _cell.x >= 0:
		world.camera.focus_on(WorldGeo.cell_center_world(_cell), false)
	if not _hud:
		var capture: CaptureMode = _main.get_node_or_null(^"CaptureMode") as CaptureMode
		if capture != null:
			capture.set_layers(CaptureMode.Layers.WORLD_ONLY)
	if _cscale > 0.0:
		_tree.root.content_scale_factor = _cscale
	Game.cmd_set_speed(_speed)
	# Зум едет твином 0.15 с, свет и вода — шейдерами: снимать раньше значит
	# снять переходное состояние, а не игру.
	for _i: int in 30:
		await _tree.process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	for i: int in _frames:
		for _j: int in _every:
			await _tree.process_frame
		await RenderingServer.frame_post_draw
		var img: Image = _tree.root.get_texture().get_image()
		var path: String = "%s/shot_%02d.png" % [_out_dir, i]
		var err: int = img.save_png(path)
		if err != OK:
			push_error("shoot: save_png %s код %d" % [path, err])
		printerr("кадр: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	_tree.quit(0)

func _wait(cond: Callable) -> bool:
	for _i: int in WAIT_FRAMES:
		if bool(cond.call()):
			return true
		await _tree.process_frame
	return false

func _die(msg: String) -> void:
	printerr("shoot: " + msg)
	_tree.quit(2)
