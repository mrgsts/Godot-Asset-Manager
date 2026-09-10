@tool
class_name IngestDialog
extends ConfirmationDialog

## Asks for the folder name a sent asset lands in.

signal confirmed_with_name(folder_name: String, vendor: String)

## The two entries the scene ships with. Saved vendors are inserted between them.
const NONE_INDEX: int = 0
const NONE_ID: int = 0
const NEW_VENDOR_ID: int = 1

@onready var _name_edit: LineEdit = $VBox/NameEdit
@onready var _error_label: Label = $VBox/ErrorLabel
@onready var _vendor_option: OptionButton = $VBox/VendorOption
@onready var _destination_label: Label = $VBox/DestinationLabel
@onready var _new_vendor_dialog: ConfirmationDialog = $NewVendorDialog
@onready var _new_vendor_edit: LineEdit = $NewVendorDialog/NewVendorBox/NewVendorEdit
@onready var _new_vendor_error: Label = $NewVendorDialog/NewVendorBox/NewVendorError

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

	_vendor_option.item_selected.connect(_on_vendor_selected)
	_new_vendor_dialog.confirmed.connect(_on_new_vendor_confirmed)
	_new_vendor_edit.text_changed.connect(_on_new_vendor_changed)
	_new_vendor_edit.text_submitted.connect(func(_text: String) -> void:
		if not _new_vendor_dialog.get_ok_button().disabled:
			_new_vendor_dialog.hide()
			_on_new_vendor_confirmed()
	)

func _apply_style() -> void:
	if not Engine.is_editor_hint():
		return
	var theme := EditorInterface.get_editor_theme()
	if theme == null:
		return

	if theme.has_color("error_color", "Editor"):
		var error_color := theme.get_color("error_color", "Editor")
		_error_label.add_theme_color_override("font_color", error_color)
		_new_vendor_error.add_theme_color_override("font_color", error_color)
	if theme.has_color("font_disabled_color", "Editor"):
		_destination_label.add_theme_color_override("font_color", theme.get_color("font_disabled_color", "Editor"))

func ask(source_path: String, bucket: String, workspace_path: String) -> void:
	_bucket = bucket
	_bucket_root = workspace_path.path_join(bucket)
	_populate_vendors(_settings.get_vendor_for_type(bucket))
	_name_edit.text = source_path.get_file().get_basename()
	_on_name_changed(_name_edit.text)
	popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()

## Saved vendors sit between the two entries the scene ships with, so "(none)"
## stays first and "New vendor..." stays last however many are added.
func _populate_vendors(preselect: String) -> void:
	_vendor_option.clear()
	_vendor_option.add_item("(none)", NONE_ID)

	var vendors := _settings.get_vendors()
	for i in vendors.size():
		_vendor_option.add_item(String(vendors[i]), i + 2)

	_vendor_option.add_item("New vendor...", NEW_VENDOR_ID)
	_vendor_option.selected = NONE_INDEX
	for i in _vendor_option.item_count:
		if _vendor_option.get_item_text(i) == preselect:
			_vendor_option.selected = i
			break

func _selected_vendor() -> String:
	if _vendor_option.selected == NONE_INDEX:
		return ""
	if _vendor_option.get_item_id(_vendor_option.selected) == NEW_VENDOR_ID:
		return ""
	return _vendor_option.get_item_text(_vendor_option.selected)

func _on_vendor_selected(index: int) -> void:
	if _vendor_option.get_item_id(index) == NEW_VENDOR_ID:
		_vendor_option.selected = NONE_INDEX
		_new_vendor_edit.text = ""
		_on_new_vendor_changed("")
		_new_vendor_dialog.popup_centered()
		_new_vendor_edit.grab_focus()
		return
	_on_name_changed(_name_edit.text)

func _on_new_vendor_changed(new_text: String) -> void:
	var vendor := new_text.strip_edges()
	var ok_button := _new_vendor_dialog.get_ok_button()

	if vendor.is_empty():
		_new_vendor_error.visible = false
		ok_button.disabled = true
		return

	if not _name_pattern.search(vendor):
		_new_vendor_error.text = "⚠ Only letters, numbers, spaces, dashes and underscores are supported."
		_new_vendor_error.visible = true
		ok_button.disabled = true
		return

	var exists := _settings.get_vendors().has(vendor)
	_new_vendor_error.text = '⚠ Vendor "%s" already exists.' % vendor
	_new_vendor_error.visible = exists
	ok_button.disabled = exists

func _on_new_vendor_confirmed() -> void:
	var vendor := _new_vendor_edit.text.strip_edges()
	if vendor.is_empty():
		return

	_settings.add_vendor(vendor)
	_populate_vendors(vendor)
	_on_name_changed(_name_edit.text)

## A pack always gets its own folder, so a name already taken is rejected here
## rather than merging into what is there.
func _on_name_changed(new_text: String) -> void:
	var folder_name := new_text.strip_edges()
	var vendor := _selected_vendor()
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
	var vendor := _selected_vendor()
	_settings.set_vendor_for_type(_bucket, vendor)
	confirmed_with_name.emit(_name_edit.text.strip_edges(), vendor)
