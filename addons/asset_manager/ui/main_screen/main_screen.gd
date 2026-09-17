@tool
@static_unload
class_name AssetManager
extends Control

## The shell. Owns the workspace, the database and the current selection, and
## wires the four components together, it draws nothing itself.
## Selection lives here rather than in the grid: the preview, the tag editor
## and the action buttons all need it, and having each reach into the grid to
## ask would couple them to whatever widget the grid happens to use.

signal asset_selected(path: String)

var current_selected_path: String = ""
var current_workspace_path: String = ""

var _workspace_picker: WorkspacePicker
var _database: AssetDatabase
var _settings: SettingsManager = SettingsManager.new()
var _thumbnails: ThumbnailCache = ThumbnailCache.new()
var _progress_dialog: ImportProgressDialog

const PROGRESS_DIALOG_SCENE := preload("res://addons/asset_manager/ui/import_progress/import_progress.tscn")

@onready var toolbar: AssetToolbar = $MarginContainer/RootVBox/Toolbar
@onready var main_split: HSplitContainer = $MarginContainer/RootVBox/MainSplit
@onready var content_split: HSplitContainer = $MarginContainer/RootVBox/MainSplit/ContentSplit
@onready var _sidebar: SidebarNavigator = $MarginContainer/RootVBox/MainSplit/Sidebar
@onready var _grid: AssetGrid = $MarginContainer/RootVBox/MainSplit/ContentSplit/CenterPanel
@onready var _preview: PreviewPanel = $MarginContainer/RootVBox/MainSplit/ContentSplit/PreviewPanel
@onready var folder_dialog: FileDialog = $FolderDialog
@onready var add_file_dialog: FileDialog = $AddFileDialog
@onready var add_dialog: AddDialog = $AddDialog
@onready var project_settings_dialog: ProjectSettingsDialog = $ProjectSettingsDialog
@onready var drop_type_menu: PopupMenu = $DropTypeMenu
@onready var tag_context_menu: PopupMenu = $TagContextMenu

func _notification(what: int) -> void:
	# Fires only when focus returns from outside the godot process.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		sync_if_stale()

func _ready() -> void:
	if EditorGuard.is_scene_tab(self):
		return

	_apply_outer_margin()
	_restore_panel_widths()

	_progress_dialog = PROGRESS_DIALOG_SCENE.instantiate()
	add_child(_progress_dialog)

	_sidebar.filter_changed.connect(_on_filter_changed)
	_sidebar.open_folder_requested.connect(func(path: String) -> void: OS.shell_open(path))
	_sidebar.add_requested.connect(_on_add_pressed)
	_grid.selection_changed.connect(_on_selection_changed)
	_grid.open_location_requested.connect(_on_open_location_pressed)
	_grid.open_external_requested.connect(_on_open_external_pressed)
	_grid.send_to_project_requested.connect(_on_send_to_project_pressed)
	_grid.add_requested.connect(_on_add_pressed)

	_preview.send_to_project_pressed.connect(_on_send_to_project_pressed)
	_preview.open_external_pressed.connect(_on_open_external_pressed)
	_preview.open_location_pressed.connect(_on_open_location_pressed)
	_preview.add_tag_requested.connect(_on_add_tag_requested)
	_preview.remove_tag_requested.connect(_on_remove_tag_requested)
	_preview.tag_search_changed.connect(_on_tag_input_text_changed)

	toolbar.search_changed.connect(func(_text: String) -> void: _on_filter_changed())
	toolbar.rebuild_pressed.connect(_on_rebuild_pressed)
	toolbar.add_pressed.connect(_on_add_pressed)
	toolbar.settings_pressed.connect(func() -> void: project_settings_dialog.open())
	project_settings_dialog.switch_workspace_requested.connect(_on_switch_workspace)
	add_file_dialog.file_selected.connect(_on_add_file_selected)
	add_dialog.confirmed_with_selection.connect(_on_add_confirmed)
	toolbar.sidebar_toggled.connect(func(collapsed: bool) -> void: _sidebar.visible = not collapsed)

	get_window().files_dropped.connect(_on_files_dropped)

	_preview.setup(_settings)
	_init_workspace_picker()

## The plugin fills the main screen the way 2D/3D/Script do, so it should sit
## as flush to the edges as they do. interface/theme/base_spacing is the
## user's own setting, the same value the editor derives its own margins from.
func _apply_outer_margin() -> void:
	var margin := 0
	if Engine.is_editor_hint():
		var spacing: int = EditorInterface.get_editor_settings().get_setting("interface/theme/base_spacing")
		margin = int(spacing * EditorInterface.get_editor_scale())

	var container: MarginContainer = $MarginContainer
	for side in ["left", "top", "right", "bottom"]:
		container.add_theme_constant_override("margin_" + side, margin)

## Widths are stored unscaled and multiplied on the way out, so a workspace
## moved between a 4K and a 1080p machine gets a sane size on each.
func _restore_panel_widths() -> void:
	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0

	main_split.split_offset = int(_settings.get_sidebar_width(SidebarNavigator.BASE_DEFAULT_WIDTH) * scale)
	content_split.split_offset = int(_settings.get_preview_width(PreviewPanel.BASE_DEFAULT_WIDTH) * scale)

	main_split.dragged.connect(func(offset: int) -> void:
		_settings.set_sidebar_width(int(offset / scale))
	)
	content_split.dragged.connect(func(offset: int) -> void:
		_settings.set_preview_width(int(offset / scale))
	)

## Called by plugin.gd when the tab is switched to.
func focus_search() -> void:
	if toolbar:
		toolbar.focus_search()

func _shortcut_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_F and (key.ctrl_pressed or key.meta_pressed):
		toolbar.focus_search_and_select()
		get_viewport().set_input_as_handled()

## Only reads index.db's version field, not the full asset list.
func sync_if_stale() -> void:
	if _database == null:
		return
	if _database.has_newer_version_on_disk():
		_database.sync()
		_refresh_all_after_index_change()
		print("AssetManager: synced, version ", _database.version, ", assets: ", _database.assets.size())

func _refresh_all_after_index_change() -> void:
	_sidebar.refresh()
	_on_filter_changed()

## The one place the sidebar's filter state and the toolbar's search meet, the
## grid is handed a plain description of what to show and never reads either.
func _on_filter_changed() -> void:
	_grid.set_filter(
		_sidebar.active_folder_prefix,
		_sidebar.active_tags,
		_sidebar.active_extensions,
		toolbar.search_text(),
		_sidebar.active_type_id
	)

## Entry point for the FileSystem dock's Send to Asset Manager, which has no
## panel of its own to rebuild from.
func rebuild_index() -> void:
	_on_rebuild_pressed()

func _on_rebuild_pressed() -> void:
	if current_workspace_path.is_empty():
		return

	# Sync must always happen before rebuild, so a rebuild from a stale local
	# base can't silently drop tag changes a teammate wrote since our last sync.
	sync_if_stale()

	toolbar.set_rebuilding(true)

	var importer := AssetImporter.new()
	importer.progress.connect(_progress_dialog.on_progress)
	_progress_dialog.start()

	var started := Time.get_ticks_msec()
	var ok := await importer.run_import(current_workspace_path, _database, self)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0

	_progress_dialog.finish()
	toolbar.set_rebuilding(false)

	if ok:
		print("AssetManager: rebuilt index: %d assets in %.1fs (by type: %s), version %d"
			% [_database.assets.size(), elapsed, importer.per_type_counts, _database.version])
		_refresh_all_after_index_change()
	else:
		push_error("AssetManager: failed to write index.db")

## A zip or a single file of the chosen type. The type is picked before the file
## so an extension shared by two buckets (.ogg, .tscn) never has to be guessed.
var _add_type_id: String = ""

func _on_add_pressed(type_id: String) -> void:
	if current_workspace_path.is_empty():
		return

	if type_id == UnrealPack.BUCKET:
		_unreal_pack_dialog().popup_centered_ratio(0.7)
		return

	_add_type_id = type_id
	var entry := AssetTypes.get_by_id(type_id)
	var extensions: Array = entry.get("extensions", [])

	var filters := PackedStringArray(["*.zip ; Asset pack"])
	if not extensions.is_empty():
		var globs: Array[String] = []
		for ext: String in extensions:
			globs.append("*." + ext)
		filters.append("%s ; %s" % [", ".join(globs), entry.get("label", type_id)])

	add_file_dialog.filters = filters
	add_file_dialog.title = "Add %s" % entry.get("label", type_id)
	add_file_dialog.popup_centered_ratio(0.7)

func _on_add_file_selected(path: String) -> void:
	add_dialog.ask(_add_type_id, path, current_workspace_path)

## The signal is window-wide with no drop position, so the plugin only claims a
## drop while its own tab is the one being looked at.
func _on_files_dropped(files: PackedStringArray) -> void:
	if not is_visible_in_tree() or current_workspace_path.is_empty():
		return
	if files.size() != 1:
		return

	var path := files[0]
	if DirAccess.dir_exists_absolute(path):
		_add_unreal_packs(path)
		return

	var candidates := AssetAdd.candidate_types(path)

	if candidates.is_empty():
		push_warning("AssetManager: nothing the library handles in " + path.get_file())
		return

	if candidates.size() == 1:
		_add_type_id = candidates[0]
		add_dialog.ask(candidates[0], path, current_workspace_path)
		return

	_ask_dropped_type(path, candidates)

## Only the buckets that could claim this file, so the choice is as short as the
## file allows: two for a shared extension, more for a mixed archive.
func _ask_dropped_type(path: String, candidates: PackedStringArray) -> void:
	drop_type_menu.clear()
	drop_type_menu.add_item("Add as…", -1)
	drop_type_menu.set_item_disabled(0, true)
	drop_type_menu.add_separator()

	for i in candidates.size():
		var entry := AssetTypes.get_by_id(candidates[i])
		var icon := IconHelper.get_icon(entry.get("default_icon", "File"))
		if icon != null:
			drop_type_menu.add_icon_item(icon, candidates[i], i)
		else:
			drop_type_menu.add_item(candidates[i], i)

	if drop_type_menu.id_pressed.is_connected(_on_dropped_type_chosen):
		drop_type_menu.id_pressed.disconnect(_on_dropped_type_chosen)
	drop_type_menu.id_pressed.connect(_on_dropped_type_chosen.bind(path, candidates))

	# files_dropped carries only the paths (window.cpp:2038), so the cursor is
	# the only record of where the drop landed.
	drop_type_menu.reset_size()
	drop_type_menu.position = DisplayServer.mouse_get_position() - drop_type_menu.size / 2
	drop_type_menu.popup()

func _on_dropped_type_chosen(id: int, path: String, candidates: PackedStringArray) -> void:
	if id < 0 or id >= candidates.size():
		return
	_add_type_id = candidates[id]
	add_dialog.ask(candidates[id], path, current_workspace_path)

## Files land first, then a rebuild indexes them. Nothing already in the index
## is re-thumbnailed, so only what just arrived costs anything.
func _on_add_confirmed(type_id: String, source_path: String, format: String, variant: String, dest_root: String) -> void:
	# Extraction is one long synchronous write, so the dialog has to paint this
	# before it starts or the editor just stops for a few seconds.
	_progress_dialog.start()
	_progress_dialog.on_progress({"stage": "scan", "label": "Extracting…", "current": 0, "total": 1})
	await get_tree().process_frame

	var result: Dictionary
	if source_path.get_extension().to_lower() == "zip":
		result = AssetAdd.extract(source_path, type_id, format, variant, dest_root)
	else:
		result = AssetExporter.new_result()
		AssetExporter.copy_one_file(source_path, dest_root.path_join(source_path.get_file()), result)

	for error_message in result["errors"]:
		push_error("AssetManager: ", error_message)

	print("AssetManager: added %d file(s) to %s" % [result["copied_count"], dest_root])

	_progress_dialog.finish()
	if result["copied_count"] > 0:
		await _on_rebuild_pressed()

var _unreal_dialog: FileDialog

func _unreal_pack_dialog() -> FileDialog:
	if _unreal_dialog == null:
		_unreal_dialog = FileDialog.new()
		_unreal_dialog.title = "Add Unreal2Godot export (a pack, or a folder of them)"
		_unreal_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_unreal_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_unreal_dialog.dir_selected.connect(_add_unreal_packs)
		add_child(_unreal_dialog)
	return _unreal_dialog

## An Unreal2Godot export is a whole Godot project and arrives as a folder, one
## pack or a folder holding several. Each is copied into unreal/ as it is, since
## its res:// paths only hold inside its own tree. Files already there are left
## alone, so adding a pack again only brings what is new.
func _add_unreal_packs(folder: String) -> void:
	var roots := UnrealPack.find_pack_roots(folder, 1)
	if roots.is_empty():
		push_warning("AssetManager: no Unreal2Godot export (project.godot with Prefabs/ and Shaders/) in " + folder)
		return

	_progress_dialog.start()
	var result := AssetExporter.new_result()
	var bucket_root := current_workspace_path.path_join(UnrealPack.BUCKET)

	for pack_root in roots:
		var dest_root := bucket_root.path_join(pack_root.get_file())
		var files := UnrealPack.list_files(pack_root)
		for i in files.size():
			AssetExporter.copy_one_file(pack_root.path_join(files[i]), dest_root.path_join(files[i]), result)
			# Thousands of files, many of them 4K textures: the editor has to keep
			# painting while they go.
			if i % 20 == 0:
				_progress_dialog.on_progress({
					"stage": "scan",
					"type": pack_root.get_file(),
					"label": files[i].get_file(),
					"current": i,
					"total": files.size(),
				})
				await get_tree().process_frame

	for error_message in result["errors"]:
		push_error("AssetManager: ", error_message)
	print("AssetManager: added %d pack(s) to %s, %d file(s) copied, %d already present"
		% [roots.size(), bucket_root, result["copied_count"], result["skipped_existing_count"]])

	_progress_dialog.finish()
	if result["copied_count"] > 0:
		await _on_rebuild_pressed()

func _on_add_tag_requested(tag_text: String) -> void:
	sync_if_stale()
	_preview.apply_tag_change(_selected_paths(), tag_text, true)
	_sidebar.refresh()

func _on_remove_tag_requested(tag_text: String) -> void:
	sync_if_stale()
	_preview.apply_tag_change(_selected_paths(), tag_text, false)

	# The tag just removed may have been the last instance anywhere.
	if not _database.get_all_known_tags().has(tag_text) and _sidebar.active_tags.has(tag_text):
		_sidebar.active_tags.erase(tag_text)
		_on_filter_changed()

	_sidebar.refresh()

func _on_tag_input_text_changed() -> void:
	_preview.refresh_tags(_selected_paths())

func _init_workspace_picker() -> void:
	_workspace_picker = preload("res://addons/asset_manager/ui/workspace_picker/workspace_picker.tscn").instantiate()
	_workspace_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_workspace_picker)
	# Only a real click builds a missing index, opening the editor on some
	# other tab shouldn't kick off a long import nobody asked for.
	_workspace_picker.workspace_opened.connect(func(path: String) -> void:
		_on_workspace_opened(path, true)
	)

	var remembered_path := _workspace_picker.try_auto_load()
	if remembered_path.is_empty():
		_show_workspace_picker(true)
	else:
		_on_workspace_opened(remembered_path, false)

## Forgets which workspace was open and returns to the picker. Nothing on disk
## is touched: the workspace is still there, it just isn't the one in front.
## Filters are cleared with it, they hold absolute paths into the workspace
## being left and would match nothing in the next one.
func _on_switch_workspace() -> void:
	AssetManagerConfig.set_value("workspace", "path", "")
	current_workspace_path = ""
	current_selected_path = ""
	_database = null

	_sidebar.active_folder_prefix = ""
	_sidebar.active_type_id = ""
	_sidebar.active_tags.clear()
	_sidebar.active_extensions.clear()
	toolbar.set_search_text("")

	_preview.clear()
	_workspace_picker.status_label.text = ""
	_show_workspace_picker(true)

func _show_workspace_picker(is_visible: bool) -> void:
	_workspace_picker.visible = is_visible
	$MarginContainer.visible = not is_visible

func _on_workspace_opened(path: String, from_picker: bool = false) -> void:
	current_workspace_path = path
	_show_workspace_picker(false)

	_database = AssetDatabase.new()
	_database.workspace_path = path
	_preview.set_database(_database)
	_sidebar.database = _database
	_sidebar.workspace_path = path
	_thumbnails.setup(path)
	_grid.setup(_database, _settings, _thumbnails)

	var had_index := _database.sync()
	print("AssetManager: workspace opened, index found: ", had_index, ", version: ", _database.version, ", assets: ", _database.assets.size())
	_refresh_all_after_index_change()

	# A workspace with no index is brand new or had one deleted, and building
	# it is the only useful next step. Deferred so the empty grid paints first:
	# going straight from the picker to a progress dialog looks like the picker
	# hung.
	if not had_index and from_picker:
		call_deferred("_on_rebuild_pressed")

## Multi-select is gone, the preview never supported it. Kept as an array
## because the tag editor still takes one.
func _selected_paths() -> Array:
	return [current_selected_path] if not current_selected_path.is_empty() else []

func _on_selection_changed(path: String) -> void:
	current_selected_path = path

	var has_selection := not path.is_empty()
	_preview.set_actions_enabled(has_selection)

	if has_selection:
		_preview.show_asset(path, _database.get_type_for_path(path))
		asset_selected.emit(path)
	else:
		_preview.clear()

	_preview.refresh_tags(_selected_paths())

func _on_open_external_pressed() -> void:
	if not current_selected_path.is_empty():
		OS.shell_open(current_selected_path)

func _on_open_location_pressed() -> void:
	if not current_selected_path.is_empty():
		OS.shell_show_in_file_manager(current_selected_path)

func _on_send_to_project_pressed() -> void:
	if current_selected_path.is_empty():
		return

	var type_id := _database.get_type_for_path(current_selected_path)
	if type_id.is_empty():
		return

	var dest_dir := project_settings_dialog.get_export_root(type_id)
	var result := AssetExporter.export_asset(current_selected_path, dest_dir, type_id, current_workspace_path)

	for error_msg in result["errors"]:
		push_error("AssetManager: ", error_msg)

	# Copied files don't show up in the FileSystem dock otherwise.
	_notify_filesystem_of_new_files(result["copied_paths"])

	var summary := str(result["copied_count"]) + " file(s) copied"
	if result["skipped_existing_count"] > 0:
		summary += ", " + str(result["skipped_existing_count"]) + " already present"
	if not result["errors"].is_empty():
		summary += ", " + str(result["errors"].size()) + " error(s)"
	_preview.flash_send_result(summary)

## scan_sources() + awaiting resources_reimported works around a Godot core
## reentrancy bug (godotengine/godot#54864). Re-test before changing it.
func _notify_filesystem_of_new_files(paths: Array) -> void:
	if paths.is_empty() or not Engine.is_editor_hint():
		return

	var efs := EditorInterface.get_resource_filesystem()
	efs.scan_sources()
	await efs.resources_reimported
