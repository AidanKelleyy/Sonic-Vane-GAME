extends SceneTree

const VALIDATOR: Script = preload("res://LS5Framework/Scripts/Managers/PlayerScriptValidation.gd")

func _initialize() -> void:
	var manifest: Dictionary = VALIDATOR.read_manifest()
	var failures: Dictionary = VALIDATOR.inspect_resources(manifest)
	if failures.is_empty():
		failures = VALIDATOR.inspect_scripts(manifest)
	for path: String in failures:
		push_error("%s: %s" % [path, failures[path]])
	print("PLAYER_STARTUP_RESULT scripts=%d failures=%d" % [manifest.get("player_scripts", []).size(), failures.size()])
	quit(1 if not failures.is_empty() else 0)
