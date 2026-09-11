@tool
class_name VendorPicker
extends OptionButton

## Chooses which vendor folder an asset lands under, and adds one that isn't
## there yet. Shared by the two dialogs that write into a bucket.

signal vendor_changed

## The two entries the list always carries. Saved vendors sit between them.
const NONE_INDEX: int = 0
const NONE_ID: int = 0
const NEW_VENDOR_ID: int = 1

@onready var _new_vendor_dialog: ConfirmationDialog = $NewVendorDialog
@onready var _new_vendor_edit: LineEdit = $NewVendorDialog/NewVendorBox/NewVendorEdit
@onready var _new_vendor_error: Label = $NewVendorDialog/NewVendorBox/NewVendorError

var _settings: SettingsManager = SettingsManager.new()

## Anything else could walk out of the bucket ("../") or nest a folder ("a/b").
var _name_pattern: RegEx = RegEx.create_from_string("^[A-Za-z0-9 _-]+$")

func _ready() -> void:
	if EditorGuard.is_scene_tab(self):
		return

	_apply_style()

	item_selected.connect(_on_item_selected)
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
	if theme != null and theme.has_color("error_color", "Editor"):
		_new_vendor_error.add_theme_color_override("font_color", theme.get_color("error_color", "Editor"))

## "(none)" stays first and "New vendor..." last, however many are added.
## A preselect that isn't saved yet joins the list, so a vendor read off a
## filename is remembered for next time.
func populate(preselect: String = "") -> void:
	if not preselect.is_empty() and not _settings.get_vendors().has(preselect):
		_settings.add_vendor(preselect)

	clear()
	add_item("(none)", NONE_ID)

	var vendors := _settings.get_vendors()
	for i in vendors.size():
		add_item(String(vendors[i]), i + 2)

	add_item("New vendor...", NEW_VENDOR_ID)

	selected = NONE_INDEX
	for i in item_count:
		if get_item_text(i) == preselect:
			selected = i
			break

func selected_vendor() -> String:
	if selected == NONE_INDEX:
		return ""
	if get_item_id(selected) == NEW_VENDOR_ID:
		return ""
	return get_item_text(selected)

func _on_item_selected(index: int) -> void:
	if get_item_id(index) == NEW_VENDOR_ID:
		selected = NONE_INDEX
		_new_vendor_edit.text = ""
		_on_new_vendor_changed("")
		_new_vendor_dialog.popup_centered()
		_new_vendor_edit.grab_focus()
		return
	vendor_changed.emit()

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
	populate(vendor)
	vendor_changed.emit()
