# ARNIX AI Developer 0.2.2

AI coding assistant dock for the Godot 4 Android Editor. The plugin reads project text files, sends a task plus context to an OpenAI-compatible chat-completions API, stages complete-file edits, checks changed GDScript syntax, creates backups, and applies the edits.

## Install as a plugin

1. Download the ZIP from the repository.
2. Extract it and copy the included `addons` folder into the root of your Godot project (merge if prompted).
3. In Godot open **Project > Project Settings > Plugins** and enable **ARNIX AI Developer**.
4. Open the ARNIX AI dock, tap ⚙, enter an OpenAI-compatible API URL, your own API key, and a model ID. Save.

The addon is a normal Godot editor plugin; it is not an APK and cannot be installed from Android Settings.

## Fixed in 0.2.2

- Fixed editor-interface access from the dock: the `EditorPlugin` now passes its `EditorInterface` reference to the dock, so the dock no longer calls `get_editor_interface()` on a `VBoxContainer`.

## Features

- Russian chat-style dock inside the editor.
- Autonomous mode and approval mode.
- Project context scan for text project files (`.gd`, `.tscn`, `.tres`, `.gdshader`, `.cfg`, `.json`, `.godot`, `.gdextension`, `.translation`).
- Multi-turn task context (last 8 requests/responses).
- Full-file create/update changes proposed by the model.
- Path restrictions, duplicate-path checks, per-file size limit, and blocked writes to `.godot` and the addon's own files.
- GDScript compilation preflight for changed `.gd` files before writing.
- Backup copies under `user://arnix_ai_backups/` before applying changes, plus an Undo button for the latest successful batch.
- Project scan button and launch-main-scene shortcut.
- OpenRouter and other OpenAI-compatible `/chat/completions` APIs.

## Limitations and safety

- This is an early plugin build, not a fully autonomous coding agent yet. It does not automatically capture Godot's complete debugger output, run an automated test suite, edit binary assets, generate images/audio, or delete files. The Run button launches the main scene; inspect Output/Debugger yourself and paste errors into the chat for AI diagnosis.
- Context scan is capped at 35 files / about 115k characters; very large projects require a future indexed/context selection feature.
- GDScript preflight is a compile check; cross-file runtime behavior still needs testing.
- API key is stored in `user://arnix_ai.cfg`. Use a dedicated limited-spend key and never commit this config.
- Autonomous mode applies edits without per-change confirmation. Keep backups and prefer approval mode for important projects.
- On Android, grant Godot Editor access to the project folder if Android asks.

## Default API

Base URL: `https://openrouter.ai/api/v1`

Example model: `openai/gpt-4o-mini`. Availability and pricing depend on the provider; choose a model available to your key.
