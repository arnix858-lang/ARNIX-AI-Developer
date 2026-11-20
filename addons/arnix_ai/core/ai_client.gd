@tool
extends RefCounted
class_name ArnixAIClient

signal completed(success: bool, result: Dictionary, message: String)

var http: HTTPRequest
var busy := false

func _init(owner: Node) -> void:
	http = HTTPRequest.new()
	http.timeout = 120.0
	owner.add_child(http)
	http.request_completed.connect(_on_request_completed)

func send_request(base_url: String, api_key: String, model: String, prompt: String) -> void:
	if busy:
		completed.emit(false, {}, "Запрос уже выполняется.")
		return
	if api_key.strip_edges().is_empty():
		completed.emit(false, {}, "Введите API-ключ в настройках аддона.")
		return
	busy = true
	var endpoint := base_url.strip_edges().trim_suffix("/")
	if not endpoint.ends_with("/chat/completions"):
		endpoint += "/chat/completions"
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key.strip_edges()
	])
	var body := {
		"model": model.strip_edges(),
		"temperature": 0.2,
		"messages": [
			{"role": "system", "content": _system_prompt()},
			{"role": "user", "content": prompt}
		]
	}
	var err := http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		completed.emit(false, {}, "Не удалось отправить запрос. Код: %s" % err)

func _system_prompt() -> String:
	return """Ты — ARNIX AI Developer, опытный разработчик Godot 4 и GDScript.
Тебе передадут описание проекта и задачу пользователя. Верни ТОЛЬКО корректный JSON без Markdown и пояснений.
Формат:
{"summary":"краткое описание","changes":[{"path":"res://путь/файл.gd","content":"ПОЛНОЕ новое содержимое файла"}]}
Правила:
1. Возвращай полное содержимое каждого изменяемого файла, не diff и не фрагменты.
2. Не изменяй файлы внутри .godot/ и сам аддон res://addons/arnix_ai/.
3. Не используй абсолютные пути, .., внешние команды, shell, OS.execute или удалённые скрипты.
4. Не выдумывай существующие классы/сигналы: опирайся на контекст проекта.
5. Если задача требует нового файла, добавь его в changes.
6. Сохраняй совместимость с Godot 4 и GDScript.
7. Не удаляй файлы. Для неясной задачи верни changes: [] и объясни вопрос в summary.
8. Не добавляй Markdown fences. Строки JSON должны быть корректно экранированы."""

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		completed.emit(false, {}, "Сетевая ошибка HTTPRequest: %s" % result)
		return
	var raw := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		completed.emit(false, {}, "Ошибка API HTTP %s: %s" % [response_code, raw.substr(0, 1200)])
		return
	var outer = JSON.parse_string(raw)
	if typeof(outer) != TYPE_DICTIONARY:
		completed.emit(false, {}, "API вернул некорректный JSON.")
		return
	var choices: Array = outer.get("choices", [])
	if choices.is_empty():
		completed.emit(false, {}, "В ответе API нет choices.")
		return
	var content = choices[0].get("message", {}).get("content", "")
	if typeof(content) != TYPE_STRING:
		completed.emit(false, {}, "Модель вернула ответ в неподдерживаемом формате.")
		return
	var cleaned: String = content.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(cleaned)
	if typeof(parsed) != TYPE_DICTIONARY:
		completed.emit(false, {}, "Не удалось разобрать ответ модели как JSON. Попробуйте другую модель.")
		return
	completed.emit(true, parsed, "Ответ получен.")
