@tool
extends RefCounted

## Captures the preview scene itself rather than rebuilding a smaller one, so
## the backdrop colour, theme loading and fit-to-view all stay in one place.
## The toolbar is the only part hidden.
## Main thread only: Control.set_theme is guarded (control.cpp:3672).

## Breathing room around the sheet, so it doesn't touch the tile edges.
const TILE_MARGIN: float = 0.9

const SHEET_SCENE := preload("res://addons/asset_manager/ui/preview_panel/types/themes/themes.tscn")

static func work_kind() -> int:
	return ThumbnailStage.WORK_VIEWPORT

static func prepare(_path: String) -> Variant:
	return null

static func render_prepared(_prepared: Variant, viewport: ThumbnailViewport, path: String) -> Image:
	var preview: Control = SHEET_SCENE.instantiate()
	preview.anchors_preset = Control.PRESET_TOP_LEFT
	preview.size = Vector2(ThumbnailCache.THUMB_SIZE, ThumbnailCache.THUMB_SIZE)

	preview.position = -preview.size * 0.5

	var holder := Node2D.new()
	holder.add_child(preview)

	viewport.host().add_child(holder)
	preview.get_node("ViewportToolbar").visible = false
	await preview.show_asset(path)
	preview.set_zoom(preview.get_zoom() * TILE_MARGIN)
	preview.center_sheet()
	viewport.host().remove_child(holder)

	return await viewport.capture_2d(holder, ThumbnailCache.THUMB_SIZE)
