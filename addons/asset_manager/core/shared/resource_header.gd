@tool
class_name ResourceHeader
extends RefCounted

## Reads what a text resource says it is on its first line. A .tres can hold
## anything, so its extension doesn't place it; the header does.

static func type_of(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""

	var first_line := file.get_line()
	file.close()

	var regex := RegEx.new()
	regex.compile('^\\[gd_resource .*type="([^"]+)"')
	var found := regex.search(first_line)
	return found.get_string(1) if found else ""
