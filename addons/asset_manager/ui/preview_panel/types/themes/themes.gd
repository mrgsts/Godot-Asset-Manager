@tool
class_name ThemesPreview
extends Control

## Applies the theme to the sheet, which propagates to every Control under it
## (control.cpp:3682). The widgets are live, so hover and pressed states are
## real rather than painted.
## Everything is defined in the scene except the Tree: TreeItem extends Object
## rather than Resource and Tree has no PropertyListHelper, so its rows cannot
## be serialised and have to be built here.

@onready var _margin: MarginContainer = $Margin
@onready var _sheet: VBoxContainer = $Margin/Sheet
@onready var _tree: Tree = $Margin/Sheet/Row6/Tree
@onready var _backdrop: ColorRect = $Backdrop
@onready var _backdrop_btn: MenuButton = $ViewportToolbar/HBox/BackdropBtn
@onready var _reset_btn: Button = $ViewportToolbar/HBox/ResetBtn

const SWATCH_SIZE: int = 16

static var BACKDROPS: Array[Dictionary] = [
	{"name": "Dark", "color": Color(0.13, 0.14, 0.16)},
	{"name": "Light", "color": Color(0.87, 0.87, 0.88)},
	{"name": "Grey", "color": Color(0.5, 0.5, 0.5)},
	{"name": "Black", "color": Color.BLACK},
	{"name": "White", "color": Color.WHITE},
]

## Where a theme's own background colours are looked for, in priority order.
## Only StyleBoxFlat has a colour to read; a textured panel has none.
const SAMPLED_STYLEBOXES: Array[Array] = [
	["panel", "Panel"],
	["panel", "PanelContainer"],
	["panel", "TabContainer"],
	["normal", "TextEdit"],
	["normal", "LineEdit"],
]
const MAX_SAMPLED: int = 4

var _backdrop_options: Array[Dictionary] = []
var _settings: SettingsManager
var _zoom: float = 1.0
var _is_panning: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	if EditorGuard.is_scene_tab(self):
		return

	_build_tree()
	resized.connect(_on_resized)

	_backdrop.visible = true
	_backdrop_btn.get_popup().id_pressed.connect(
		func(id: int) -> void: _set_backdrop(_backdrop_options[id]["color"]))
	_reset_btn.pressed.connect(_reset_view)
	_rebuild_backdrop_menu(null)

	IconHelper.apply(_backdrop_btn, "ColorRect")
	IconHelper.apply(_reset_btn, "CenterView")
	_set_backdrop(BACKDROPS[0]["color"])

func setup(p_settings: SettingsManager) -> void:
	_settings = p_settings

func show_asset(path: String, _type_entry: Dictionary = {}) -> void:
	visible = true

	var theme := TscnSceneLoader.load_resource_external(path, "themes") as Theme
	_sheet.theme = theme
	_rebuild_backdrop_menu(theme)

	_zoom = 1.0
	_apply_zoom()
	await get_tree().process_frame
	_zoom = _fit_zoom()
	_apply_zoom()
	_center_sheet()

func hide_asset() -> void:
	visible = false
	_sheet.theme = null

func get_zoom() -> float:
	return _zoom

func set_zoom(zoom: float) -> void:
	_zoom = zoom
	_apply_zoom()

func center_sheet() -> void:
	_center_sheet()

func _apply_zoom() -> void:
	_margin.scale = Vector2(_zoom, _zoom)

## Shrinks to fit a panel too small for the sheet, never magnifies: 1.0 is the
## theme at its authored size, which is the honest view.
func _fit_zoom() -> float:
	var content := _margin.get_combined_minimum_size()
	if content.x <= 0.0 or content.y <= 0.0:
		return 1.0
	return minf(1.0, minf(size.x / content.x, size.y / content.y))

func _center_sheet() -> void:
	if not is_instance_valid(_margin):
		return
	_margin.size = _margin.get_combined_minimum_size()
	_margin.position = (size - _margin.size * _zoom) * 0.5

func _on_resized() -> void:
	_center_sheet()

func _rebuild_backdrop_menu(theme: Theme) -> void:
	_backdrop_options = BACKDROPS.duplicate()

	var sampled := _sample_theme_colours(theme)
	if not sampled.is_empty():
		_backdrop_options.append_array(sampled)
		_set_backdrop(sampled[0]["color"])
	else:
		_set_backdrop(BACKDROPS[0]["color"])

	var popup := _backdrop_btn.get_popup()
	popup.clear()
	for i in range(_backdrop_options.size()):
		if i == BACKDROPS.size():
			popup.add_separator("From theme")
		var entry: Dictionary = _backdrop_options[i]
		popup.add_icon_item(_swatch(entry["color"]), entry["name"], i)

func _sample_theme_colours(theme: Theme) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if theme == null:
		return found

	for pair in SAMPLED_STYLEBOXES:
		if found.size() >= MAX_SAMPLED:
			break
		if not theme.has_stylebox(pair[0], pair[1]):
			continue
		var box := theme.get_stylebox(pair[0], pair[1]) as StyleBoxFlat
		if box == null:
			continue
		var colour := box.bg_color
		if found.any(func(e: Dictionary) -> bool: return e["color"] == colour):
			continue
		found.append({"name": pair[1], "color": colour})

	return found

func _swatch(colour: Color) -> ImageTexture:
	var img := Image.create_empty(SWATCH_SIZE, SWATCH_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	return ImageTexture.create_from_image(img)

func _set_backdrop(colour: Color) -> void:
	_backdrop.color = colour
	_backdrop_btn.add_theme_color_override("icon_normal_color", colour)
	_backdrop_btn.add_theme_color_override("icon_hover_color", colour)
	_backdrop_btn.add_theme_color_override("icon_pressed_color", colour)

func _reset_view() -> void:
	_zoom = 1.0
	_apply_zoom()
	_center_sheet()

func handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.1)

	elif event is InputEventMouseMotion and _is_panning:
		var motion := event as InputEventMouseMotion
		_margin.position += motion.position - _last_mouse_pos
		_last_mouse_pos = motion.position

func _zoom_at(mouse_pos: Vector2, factor: float) -> void:
	var old_scale := _margin.scale
	var new_scale := (old_scale * factor).clampf(0.2, 8.0)

	var mouse_local := mouse_pos - _margin.position
	_margin.position -= mouse_local * ((new_scale / old_scale) - Vector2.ONE)
	_margin.scale = new_scale
	_zoom = new_scale.x

func _build_tree() -> void:
	_tree.clear()
	_tree.set_column_expand(0, false)
	_tree.set_column_expand(1, false)

	var root := _new_item(null, "Tree")

	_new_item(root, "Resolution", "1600x1200")
	_new_item(root, "Vertical Sync", "On")

	var editable := _new_item(root, "Editable", "Placeholder")
	editable.set_editable(1, true)

	var branch := _new_item(root, "Subtree")

	var checked := _new_item(branch, "Check item")
	checked.set_cell_mode(1, TreeItem.CELL_MODE_CHECK)
	checked.set_checked(1, true)
	checked.set_editable(1, true)

## Cells trim to an ellipsis by default (tree.h:133), which cuts the text long
## before the column runs out of room.
func _new_item(parent: TreeItem, first: String, second: String = "") -> TreeItem:
	var item := _tree.create_item(parent)
	item.set_text(0, first)
	item.set_text_overrun_behavior(0, TextServer.OVERRUN_NO_TRIMMING)
	if not second.is_empty():
		item.set_text(1, second)
	item.set_text_overrun_behavior(1, TextServer.OVERRUN_NO_TRIMMING)
	return item
