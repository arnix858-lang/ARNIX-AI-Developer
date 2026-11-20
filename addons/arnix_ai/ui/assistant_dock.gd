@tool
extends VBoxContainer

const ContextScript = preload("res://addons/arnix_ai/core/project_context.gd")
const ClientScript = preload("res://addons/arnix_ai/core/ai_client.gd")
const ChangeScript = preload("res://addons/arnix_ai/core/change_manager.gd")

var client
var change_manager
var context_reader
var task_input: TextEdit
var chat_log: RichTextLabel
var mode_button: CheckButton
var settings_panel: VBoxContainer
var base_input: LineEdit
var key_input: LineEdit
var model_input: LineEdit
var pending_changes: Array[Dictionary] = []
var pending_summary := ""
var conversation_history: Array[String] = []
var preview_box: TextEdit
var repair_attempts := 0
var busy_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(300, 420)
	context_reader = ContextScript.new()
	change_manager = ChangeScript.new()
	change_manager.changes_applied.connect(_on_changes_applied)
	change_manager.apply_failed.connect(_on_apply_failed)
	client = ClientScript.new(self)
	client.completed.connect(_on_ai_completed)
	_build_ui()
	_load_settings()
	_log("[b]ARNIX AI Developer 0.2.1[/b]\nОпишите изменение проекта обычным языком. Сначала ИИ изучит файлы проекта.")

func _build_ui() -> void:
	var header := HBoxContainer.new()
	add_child(header)
	var title := Label.new()
	title.text = "✦ ARNIX AI Developer"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var settings_btn := Button.new()
	settings_btn.text = "⚙"
	settings_btn.tooltip_text = "Настройки API"
	settings_btn.pressed.connect(_toggle_settings)
	header.add_child(settings_btn)

	mode_button = CheckButton.new()
	mode_button.text = "Автономный режим"
	mode_button.tooltip_text = "Включено: применить изменения автоматически. Выключено: сначала показать план и запросить подтверждение."
	add_child(mode_button)

	settings_panel = VBoxContainer.new()
	settings_panel.visible = false
	add_child(settings_panel)
	_add_setting("API URL", "https://openrouter.ai/api/v1", false)
	_add_setting("API ключ", "", true)
	_add_setting("Модель", "openai/gpt-4o-mini", false)
	var save_btn := Button.new()
	save_btn.text = "Сохранить настройки"
	save_btn.pressed.connect(_save_settings)
	settings_panel.add_child(save_btn)

	var chat_title := Label.new()
	chat_title.text = "Диалог"
	add_child(chat_title)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.fit_content = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.custom_minimum_size = Vector2(0, 160)
	add_child(chat_log)

	var task_title := Label.new()
	task_title.text = "Ваше задание"
	add_child(task_title)
	task_input = TextEdit.new()
	task_input.placeholder_text = "Например: добавь игроку двойной прыжок и анимацию..."
	task_input.custom_minimum_size = Vector2(0, 90)
	add_child(task_input)

	var actions := HBoxContainer.new()
	add_child(actions)
	var send_btn := Button.new()
	send_btn.text = "Отправить задачу"
	send_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_btn.pressed.connect(_send_task)
	actions.add_child(send_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Очистить"
	clear_btn.pressed.connect(func(): task_input.text = "")
	actions.add_child(clear_btn)

	busy_label = Label.new()
	busy_label.text = "Готов"
	add_child(busy_label)

	var utility_actions := HBoxContainer.new()
	add_child(utility_actions)
	var scan_btn := Button.new()
	scan_btn.text = "Сканировать проект"
	scan_btn.pressed.connect(_scan_project)
	utility_actions.add_child(scan_btn)
	var run_btn := Button.new()
	run_btn.text = "Запустить игру"
	run_btn.pressed.connect(_run_project)
	utility_actions.add_child(run_btn)
	var preview_title := Label.new()
	preview_title.text = "Предпросмотр выбранного изменения"
	add_child(preview_title)
	preview_box = TextEdit.new()
	preview_box.editable = false
	preview_box.custom_minimum_size = Vector2(0, 110)
	add_child(preview_box)

	var pending_actions := HBoxContainer.new()
	add_child(pending_actions)
	var apply_btn := Button.new()
	apply_btn.text = "Применить изменения"
	apply_btn.pressed.connect(_apply_pending)
	pending_actions.add_child(apply_btn)
	var discard_btn := Button.new()
	discard_btn.text = "Отклонить"
	discard_btn.pressed.connect(_discard_pending)
	pending_actions.add_child(discard_btn)
	var undo_btn := Button.new()
	undo_btn.text = "Откатить"
	undo_btn.pressed.connect(_undo_last_change)
	pending_actions.add_child(undo_btn)

func _add_setting(label_text: String, default_text: String, secret: bool) -> void:
	var label := Label.new()
	label.text = label_text
	settings_panel.add_child(label)
	var field := LineEdit.new()
	field.text = default_text
	field.secret = secret
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_panel.add_child(field)
	if label_text == "API URL":
		base_input = field
	elif label_text == "API ключ":
		key_input = field
	else:
		model_input = field

func _toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://arnix_ai.cfg") == OK:
		base_input.text = str(cfg.get_value("api", "base_url", base_input.text))
		key_input.text = str(cfg.get_value("api", "key", ""))
		model_input.text = str(cfg.get_value("api", "model", model_input.text))
		mode_button.button_pressed = bool(cfg.get_value("general", "autonomous", false))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("api", "base_url", base_input.text.strip_edges())
	cfg.set_value("api", "key", key_input.text)
	cfg.set_value("api", "model", model_input.text.strip_edges())
	cfg.set_value("general", "autonomous", mode_button.button_pressed)
	var err := cfg.save("user://arnix_ai.cfg")
	_log("Настройки сохранены." if err == OK else "Ошибка сохранения настроек: %s" % err)

func _send_task() -> void:
	var task := task_input.text.strip_edges()
	if task.is_empty():
		_log("Сначала напишите задание.")
		return
	if client.busy:
		_log("Подождите завершения текущего запроса.")
		return
	_save_settings()
	repair_attempts = 0
	busy_label.text = "Анализирую проект и обращаюсь к модели..."
	_log("[b]Вы:[/b] " + task)
	var context: Dictionary = context_reader.collect_project_context()
	var history_text := "\n".join(PackedStringArray(conversation_history.slice(maxi(0, conversation_history.size() - 8))))
	var prompt := "ПРЕДЫДУЩИЙ ДИАЛОГ:\n%s\n\nНОВАЯ ЗАДАЧА ПОЛЬЗОВАТЕЛЯ:\n%s\n\nКОНТЕКСТ ПРОЕКТА (файлы и содержимое):\n%s\n\nОграничения: верни только JSON по системному формату. Не меняй файлы, не относящиеся к задаче." % [history_text, task, JSON.stringify(context)]
	conversation_history.append("Пользователь: " + task)
	client.send_request(base_input.text, key_input.text, model_input.text, prompt)

func _on_ai_completed(success: bool, result: Dictionary, message: String) -> void:
	busy_label.text = "Готово" if success else "Ошибка"
	if not success:
		_log("[color=tomato]Ошибка: %s[/color]" % message)
		return
	pending_summary = str(result.get("summary", "Изменения подготовлены."))
	var validation: Dictionary = change_manager.validate_changes(result.get("changes", []))
	if not validation.ok:
		_log("[color=tomato]Отклонено: %s[/color]" % validation.error)
		return
	pending_changes = validation.changes
	_log("[b]ARNIX AI:[/b] " + pending_summary)
	conversation_history.append("ARNIX AI: " + pending_summary)
	if pending_changes.is_empty():
		_log("Модель не предложила изменений файлов.")
		return
	_log("Подготовлено файлов: %d" % pending_changes.size())
	for item in pending_changes:
		_log("• " + item.path)
	if not pending_changes.is_empty():
		preview_box.text = "Файл: %s\n\n%s" % [pending_changes[0].path, pending_changes[0].content]
	if mode_button.button_pressed:
		_log("[color=orange]Автономный режим: применяю изменения...[/color]")
		_apply_pending()
	else:
		_log("[color=yellow]Режим подтверждения: проверьте список и нажмите «Применить изменения».[/color]")

func _apply_pending() -> void:
	if pending_changes.is_empty():
		_log("Нет ожидающих изменений.")
		return
	var to_apply := pending_changes.duplicate(true)
	if change_manager.apply_changes(to_apply):
		pending_changes.clear()
		preview_box.text = ""
		_save_settings()
		EditorInterface.get_resource_filesystem().scan()

func _undo_last_change() -> void:
	if change_manager.restore_last_backup():
		EditorInterface.get_resource_filesystem().scan()
		_log("Последнее изменение отменено из резервной копии.")

func _discard_pending() -> void:
	pending_changes.clear()
	preview_box.text = ""
	_log("Подготовленные изменения отклонены.")

func _scan_project() -> void:
	var context: Dictionary = context_reader.collect_project_context()
	_log("Сканирование завершено. Найдено текстовых файлов: %d. Godot: %s" % [context.files.size(), str(context.godot_version)])

func _run_project() -> void:
	EditorInterface.play_main_scene()
	_log("Запрошен запуск главной сцены. Сообщения выполнения смотрите в панели Output/Debugger Godot.")

func _on_changes_applied(count: int, backup_folder: String) -> void:
	repair_attempts = 0
	_log("[color=lightgreen]Успешно изменено файлов: %d[/color]" % count)
	_log("Резервные копии: " + backup_folder)
	busy_label.text = "Изменения применены"

func _on_apply_failed(message: String) -> void:
	_log("[color=tomato]Ошибка записи: %s[/color]" % message)
	if message.begins_with("Проверка GDScript") and repair_attempts < 2 and not pending_changes.is_empty():
		repair_attempts += 1
		_request_syntax_repair(message)

func _request_syntax_repair(error_text: String) -> void:
	busy_label.text = "ИИ исправляет ошибку компиляции..."
	var context: Dictionary = context_reader.collect_project_context()
	var prompt := "Предыдущая версия изменений не прошла проверку GDScript. Исправь ошибки, сохранив цель пользователя.\nОШИБКА ПРОВЕРКИ:\n%s\n\nИЗМЕНЕНИЯ, КОТОРЫЕ НУЖНО ИСПРАВИТЬ:\n%s\n\nКОНТЕКСТ ТЕКУЩЕГО ПРОЕКТА:\n%s\n\nВерни только JSON с полными содержимыми исправленных файлов по стандартной схеме." % [error_text, JSON.stringify(pending_changes), JSON.stringify(context)]
	client.send_request(base_input.text, key_input.text, model_input.text, prompt)

func _log(message: String) -> void:
	if is_instance_valid(chat_log):
		chat_log.append_text(message + "\n\n")
