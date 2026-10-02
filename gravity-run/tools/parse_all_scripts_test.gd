extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_scan_project")

func _scan_project() -> void:
	_scan_directory("res://")
	if failures.is_empty():
		print("All GDScript files parsed successfully.")
		quit()
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _scan_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		failures.append("Could not read %s" % path)
		return
	for filename in directory.get_files():
		if not filename.ends_with(".gd"):
			continue
		var script_path := path.path_join(filename)
		var script := ResourceLoader.load(script_path) as GDScript
		if script == null:
			failures.append("Could not parse %s" % script_path)
		elif not script.can_instantiate():
			failures.append("Script is not instantiable after parse: %s" % script_path)
	for folder in directory.get_directories():
		if folder.begins_with("."):
			continue
		_scan_directory(path.path_join(folder))
