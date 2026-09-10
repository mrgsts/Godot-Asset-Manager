@tool
class_name AssetManagerContextMenu
extends EditorContextMenuPlugin

## Adds "Send to Asset Manager" to the FileSystem dock's right-click menu.

const DIALOG_SCENE := preload("res://addons/asset_manager/ui/ingest_dialog/ingest_dialog.tscn")

## Set by plugin.gd. The index is rebuilt through the panel because that is
## where the database and the viewport the thumbnails render into live.
var main_panel: Control

func _popup_menu(paths: PackedStringArray) -> void:
	if paths.size() != 1:
		return

	var buckets := buckets_for(paths[0])
	if buckets.is_empty():
		return

	if buckets.size() == 1:
		add_context_menu_item("Send to Asset Manager", _on_send.bind(buckets[0]), _bucket_icon(buckets[0]))
		return

	# The submenu is freed on every popup, so it's built fresh here and its
	# signal connected by hand: neither is done for us.
	var submenu := PopupMenu.new()
	for i in buckets.size():
		var entry := AssetTypes.get_by_id(buckets[i])
		submenu.add_icon_item(_bucket_icon(buckets[i]), entry.get("label", buckets[i]), i)
	submenu.id_pressed.connect(func(id: int) -> void: _on_send(paths, buckets[id]))
	add_context_submenu_item("Send to Asset Manager", submenu, IconHelper.get_icon("Load"))

## The same icon the grid gives that type, so the menu says where the file is
## going rather than only that it is going somewhere.
static func _bucket_icon(bucket: String) -> Texture2D:
	var name: String = AssetTypes.get_by_id(bucket).get("default_icon", "")
	var icon := IconHelper.get_icon(name) if not name.is_empty() else null
	return icon if icon != null else IconHelper.get_icon("Load")

func _on_send(paths: PackedStringArray, bucket: String) -> void:
	var workspace_path: String = AssetManagerConfig.get_value("workspace", "path", "")
	if workspace_path.is_empty():
		push_warning("AssetManager: no workspace open, nothing to send to.")
		return

	var dialog: IngestDialog = DIALOG_SCENE.instantiate()
	EditorInterface.get_base_control().add_child(dialog)
	dialog.confirmed_with_name.connect(func(folder_name: String, vendor: String) -> void:
		_run_ingest(paths[0], bucket, folder_name, workspace_path, vendor)
		dialog.queue_free()
		if main_panel != null and main_panel.has_method("rebuild_index"):
			main_panel.rebuild_index()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.ask(paths[0], bucket, workspace_path)

static func _run_ingest(source_path: String, bucket: String, folder_name: String, workspace_path: String, vendor: String) -> void:
	var result := AssetIngest.ingest_asset(source_path, bucket, folder_name, workspace_path, vendor)

	for error: String in result["errors"]:
		push_warning("AssetManager: " + error)

	var below := folder_name if vendor.is_empty() else vendor.path_join(folder_name)
	print("AssetManager: sent %d file(s) to %s/%s" % [result["copied_count"], bucket, below])

## Every bucket whose extension list claims this file. One means no question to
## ask; two (audio, .tscn) means the user picks; a .tres is decided by its header.
static func buckets_for(path: String) -> PackedStringArray:
	var extension := path.get_extension().to_lower()
	var found := PackedStringArray()

	for entry in AssetTypes.ALL:
		var id: String = entry["id"]
		if id == AssetTypes.FALLBACK_ID:
			continue

		var extensions: Array = entry.get("extensions", [])
		if not extensions.has(extension):
			continue

		var wanted: Array = entry.get("resource_type", [])
		if wanted.is_empty() or wanted.has(ResourceHeader.type_of(path)):
			found.append(id)

	return found
