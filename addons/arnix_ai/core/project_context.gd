@tool
extends RefCounted
class_name ArnixProjectContext

const ALLOWED_EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "cfg", "json", "godot", "gdextension", "translation"]
const SKIP_DIRS := [".git", ".godot", ".import", "node_modules", "android", "ios"]
const MAX_FILES := 35
const MAX_TOTAL_CHARS := 115000
const MAX_FILE_CHARS := 18000

func collect_project_context() -> Dictionary:
	var files: Array[Dictionary] = []
	var total_chars := _scan("res://", files, 0)
	var truncated := files.size() >= MAX_FILES or total_chars >= MAX_TOTAL_CHARS
	return {
		"project_name": ProjectSettings.get_setting("application/config/name", "Godot Project"),
		"godot_version": Engine.get_version_info(),
		"files": files,
		"truncated": truncated,
		"project_settings": {
			"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
		}
	}

func _scan(path: String, output: Array[Dictionary], total_chars: int) -> int:
	if output.size() >= MAX_FILES or total_chars >= MAX_TOTAL_CHARS:
		return total_chars
	var dir := DirAccess.open(path)
	if dir == null:
		return total_chars
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(".") and entry != ".gdignore":
			entry = dir.get_next()
			continue
		var full_path := path.path_join(entry)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(entry):
				total_chars = _scan(full_path, output, total_chars)
		else:
			var ext := entry.get_extension().to_lower()
			if ALLOWED_EXTENSIONS.has(ext) and not entry.ends_with(".uid"):
				var file := FileAccess.open(full_path, FileAccess.READ)
				if file != null:
					var content := file.get_as_text()
					file.close()
					if content.length() > MAX_FILE_CHARS:
						content = content.substr(0, MAX_FILE_CHARS) + "\n[FILE TRUNCATED]"
					if total_chars + content.length() <= MAX_TOTAL_CHARS and output.size() < MAX_FILES:
						output.append({"path": full_path, "content": content})
						total_chars += content.length()
		entry = dir.get_next()
	dir.list_dir_end()
	return total_chars
