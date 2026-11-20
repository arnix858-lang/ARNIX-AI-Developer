@tool
extends EditorPlugin

const DOCK_SCRIPT = preload("res://addons/arnix_ai/ui/assistant_dock.gd")
var dock: Control

func _enter_tree() -> void:
	dock = DOCK_SCRIPT.new()
	dock.name = "ARNIX AI"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()
