@tool
class_name TypeMenu
extends RefCounted

## Fills a PopupMenu with the asset types, for the two places that offer
## "add one of these". Returns the ids in menu order, so an item's id is its
## index back into that list.

## Last entry, not a type: a folder linked in place (AssetLink), whichever
## bucket its files belong to.
const FOLDER_ID: String = "__folder__"

## Every type but the "other" fallback, which nothing can deliberately be.
## Each carries the icon the grid gives it, so the menu says what it will add.
static func populate(popup: PopupMenu) -> Array[String]:
	popup.clear()

	var type_ids: Array[String] = []
	for type_entry in AssetTypes.ALL:
		var type_id: String = type_entry["id"]
		if type_id == AssetTypes.FALLBACK_ID:
			continue

		var icon := IconHelper.get_icon(type_entry.get("default_icon", "File"))
		if icon != null:
			popup.add_icon_item(icon, type_id, type_ids.size())
		else:
			popup.add_item(type_id, type_ids.size())
		type_ids.append(type_id)

	popup.add_separator()
	var folder_icon := IconHelper.get_icon("Folder")
	if folder_icon != null:
		popup.add_icon_item(folder_icon, "Folder (link)…", type_ids.size())
	else:
		popup.add_item("Folder (link)…", type_ids.size())
	type_ids.append(FOLDER_ID)

	return type_ids
