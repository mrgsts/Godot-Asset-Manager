@tool
class_name ThemesExportHandler
extends RefCounted

## A theme is a .tres referencing styleboxes, textures and fonts with baked
## res:// paths, the same dependency problem effects packs have. The walk in
## effects/export.gd already handles .tres and derives the pack root from the
## destination folder rather than a bucket name, so it needs no changes here.
static func export_asset(source_path: String, dest_path: String, bucket: String = "themes") -> Dictionary:
	return EffectsExportHandler.export_asset(source_path, dest_path, bucket)
