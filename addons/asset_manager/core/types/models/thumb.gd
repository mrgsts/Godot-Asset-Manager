@tool
extends RefCounted

## Thumbnail renderer for models. Same load path as models.gd's preview, then
## hands the node tree to the shared viewport for capture.
## Parsing runs on a worker; only the capture is main-thread (GltfSceneLoader
## explains why that is safe). Worth ~4 seconds on a few hundred models.

static func work_kind() -> int:
	return ThumbnailStage.WORK_VIEWPORT

static func prepare(path: String) -> Variant:
	return GltfSceneLoader.load_external(path)

## Models only capture plain geometry, nothing here reconfigures the viewport
## like sky/fog, the batch can use the main one as a slot.
static func reuses_main_viewport() -> bool:
	return true

## Already parsed by prepare() on a worker, hands it over so the stage can
## render a whole chunk in one frame (ThumbnailViewport.capture_batch).
static func build_subject(prepared: Variant, path: String) -> Node3D:
	if prepared is Node3D:
		return prepared as Node3D
	# prepare() failed or wasn't run for this one.
	return GltfSceneLoader.load_external(path)

static func render_prepared(prepared: Variant, viewport: ThumbnailViewport, path: String = "") -> Image:
	var subject: Node3D = prepared as Node3D if prepared is Node3D else GltfSceneLoader.load_external(path)
	if subject == null:
		return null
	return await viewport.capture(subject)
