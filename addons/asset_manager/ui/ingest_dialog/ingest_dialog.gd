@tool
class_name IngestDialog
extends ConfirmationDialog

## Asks for the folder name a sent asset lands in.

signal confirmed_with_name(folder_name: String, vendor: String)

@onready var _name_edit: LineEdit = $VBox/NameEdit
@onready var _error_label: Label = $VBox/ErrorLabel
@onready var _vendor_option: VendorPicker = $VBox/VendorOption
@onready var _destination_label: Label = $VBox/DestinationLabel

var _settings: SettingsManager = SettingsManager.new()
var _bucket_root: String = ""
var _bucket: String = ""

## Anything else could walk out of the workspace ("../"), nest a folder ("a/b"),
## or hide the pack from the scanner, which skips dot-folders.
var _name_pattern: RegEx = RegEx.create_from_string("^[A-Za-z0-9 _-]+$")

func _ready() -> void:
	if EditorGuard.is_scene_tab(self):
		return

	_apply_style()

	confirmed.connect(_on_confirmed)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_text: String) -> void:
		if not get_ok_button().disabled:
			hide()
			_on_confirmed()
	)

	_vendor_option.vendor_changed.connect(func() -> void: _on_name_changed(_name_edit.text))

func _apply_style() -> void:
	if not Engine.is_editor_hint():
		return
	var theme := EditorInterface.get_editor_theme()
	if theme == null:
		return

	if theme.has_color("error_color", "Editor"):
		_error_label.add_theme_color_override("font_color", theme.get_color("error_color", "Editor"))
	if theme.has_color("font_disabled_color", "Editor"):
		_destination_label.add_theme_color_override("font_color", theme.get_color("font_disabled_color", "Editor"))

func ask(source_path: String, bucket: String, workspace_path: String) -> void:
	_bucket = bucket
	_bucket_root = workspace_path.path_join(bucket)
	_vendor_option.populate(_settings.get_vendor_for_type(bucket))
	_name_edit.text = source_path.get_file().get_basename()
	_on_name_changed(_name_edit.text)
	popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()

## A pack always gets its own folder, so a name already taken is rejected here
## rather than merging into what is there.
func _on_name_changed(new_text: String) -> void:
	var folder_name := new_text.strip_edges()
	var vendor := _vendor_option.selected_vendor()
	var root := _bucket_root if vendor.is_empty() else _bucket_root.path_join(vendor)

	if folder_name.is_empty():
		_destination_label.text = root
		_error_label.visible = false
		get_ok_button().disabled = true
		return

	if not _name_pattern.search(folder_name):
		_destination_label.text = root
		_error_label.text = "⚠ Only letters, numbers, spaces, dashes and underscores are supported."
		_error_label.visible = true
		get_ok_button().disabled = true
		return

	var destination := root.path_join(folder_name)
	var taken := DirAccess.dir_exists_absolute(destination)

	_destination_label.text = destination
	_error_label.text = '⚠ Folder "%s" already exists.' % folder_name
	_error_label.visible = taken
	get_ok_button().disabled = taken

func _on_confirmed() -> void:
	var vendor := _vendor_option.selected_vendor()
	_settings.set_vendor_for_type(_bucket, vendor)
	confirmed_with_name.emit(_name_edit.text.strip_edges(), vendor)
