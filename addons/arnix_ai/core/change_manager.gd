@tool
extends RefCounted
class_name ArnixChangeManager

signal changes_applied(count: int, backup_folder: String)
signal apply_failed(message: String)

const MAX_CHANGES := 30
const MAX_FILE_BYTES := 512000
var last_backup_folder := ""

func validate_changes(changes: Variant) -> Dictionary:
	if typeof(changes) != TYPE_ARRAY:
		return {"ok": false, "error": "Поле changes должно быть массивом."}
	if changes.size() > MAX_CHANGES:
		return {"ok": false, "error": "Слишком много изменений за один запрос (максимум %d)." % MAX_CHANGES}
	var validated: Array[Dictionary] = []
	var seen := {}
	for item in changes:
		if typeof(item) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Некорректный элемент changes."}
		var path := str(item.get("path", ""))
		var content = item.get("content", null)
		if not path.begins_with("res://") or path.contains("..") or path.contains("\\") or path.trim_prefix("res://").contains("://"):
			return {"ok": false, "error": "Запрещённый путь: " + path}
		if path.begins_with("res://.godot/") or path.begins_with("res://addons/arnix_ai/"):
			return {"ok": false, "error": "Изменение системных файлов и самого аддона запрещено: " + path}
		if seen.has(path):
			return {"ok": false, "error": "Повторяющийся путь: " + path}
		if typeof(content) != TYPE_STRING:
			return {"ok": false, "error": "Для файла %s отсутствует текстовое содержимое." % path}
		if content.to_utf8_buffer().size() > MAX_FILE_BYTES:
			return {"ok": false, "error": "Файл слишком большой: " + path}
		seen[path] = true
		validated.append({"path": path, "content": content})
	return {"ok": true, "changes": validated}

func validate_gdscript_changes(changes: Array[Dictionary]) -> Dictionary:
	var issues: Array[String] = []
	for item in changes:
		if str(item.path).get_extension().to_lower() != "gd":
			continue
		var script := GDScript.new()
		script.source_code = str(item.content)
		var err := script.reload()
		if err != OK:
			issues.append("%s: не прошёл компиляцию GDScript (код %d). Проверьте синтаксис и зависимости." % [item.path, err])
	if issues.is_empty():
		return {"ok": true, "issues": []}
	return {"ok": false, "issues": issues}

func apply_changes(changes: Array[Dictionary]) -> bool:
	var syntax := validate_gdscript_changes(changes)
	if not syntax.ok:
		apply_failed.emit("Проверка GDScript не пройдена:\n" + "\n".join(PackedStringArray(syntax.issues)))
		return false
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var backup_root := "user://arnix_ai_backups/" + stamp
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_root))
	# Create all backups before writing any project file.
	var manifest: Array[Dictionary] = []
	for change in changes:
		var path: String = change.path
		var existed := FileAccess.file_exists(path)
		manifest.append({"path": path, "existed": existed})
		if existed:
			var backup_path := backup_root.path_join(path.trim_prefix("res://"))
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_path.get_base_dir()))
			var old_file := FileAccess.open(path, FileAccess.READ)
			if old_file == null:
				apply_failed.emit("Не удалось прочитать исходный файл: " + path)
				return false
			var old_content := old_file.get_buffer(old_file.get_length())
			old_file.close()
			var backup := FileAccess.open(backup_path, FileAccess.WRITE)
			if backup == null:
				apply_failed.emit("Не удалось создать резервную копию: " + backup_path)
				return false
			backup.store_buffer(old_content)
			backup.close()
	var manifest_file := FileAccess.open(backup_root.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		apply_failed.emit("Не удалось сохранить манифест резервной копии.")
		return false
	manifest_file.store_string(JSON.stringify(manifest))
	manifest_file.close()
	# Write files only after the backup pass succeeded.
	for change in changes:
		var path: String = change.path
		var mk_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		if mk_err != OK and mk_err != ERR_ALREADY_EXISTS:
			apply_failed.emit("Не удалось создать папку: " + path.get_base_dir())
			return false
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			apply_failed.emit("Не удалось записать файл: " + path)
			return false
		file.store_string(change.content)
		file.close()
	last_backup_folder = backup_root
	changes_applied.emit(changes.size(), backup_root)
	return true

func restore_last_backup() -> bool:
	if last_backup_folder.is_empty():
		apply_failed.emit("Нет резервной копии для отката в этой сессии.")
		return false
	var manifest_path := last_backup_folder.path_join("manifest.json")
	var mf := FileAccess.open(manifest_path, FileAccess.READ)
	if mf == null:
		apply_failed.emit("Не найден манифест резервной копии.")
		return false
	var parsed = JSON.parse_string(mf.get_as_text())
	mf.close()
	if typeof(parsed) != TYPE_ARRAY:
		apply_failed.emit("Манифест резервной копии повреждён.")
		return false
	for entry in parsed:
		var path := str(entry.get("path", ""))
		if bool(entry.get("existed", false)):
			var backup_path := last_backup_folder.path_join(path.trim_prefix("res://"))
			var backup := FileAccess.open(backup_path, FileAccess.READ)
			if backup == null:
				apply_failed.emit("Не найдена копия файла: " + path)
				return false
			var bytes := backup.get_buffer(backup.get_length())
			backup.close()
			var restored := FileAccess.open(path, FileAccess.WRITE)
			if restored == null:
				apply_failed.emit("Не удалось восстановить файл: " + path)
				return false
			restored.store_buffer(bytes)
			restored.close()
		elif FileAccess.file_exists(path):
			var abs_path := ProjectSettings.globalize_path(path)
			var remove_err := DirAccess.remove_absolute(abs_path)
			if remove_err != OK:
				apply_failed.emit("Не удалось удалить созданный файл при откате: " + path)
				return false
	last_backup_folder = ""
	changes_applied.emit(parsed.size(), "Откат выполнен")
	return true
