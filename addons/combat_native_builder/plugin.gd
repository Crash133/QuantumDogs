@tool
extends EditorPlugin

func _enter_tree() -> void:
	resource_saved.connect(_on_resource_saved)
	_build_native_extension()

func _exit_tree() -> void:
	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)

# Authoring check: weapon mistakes surface in Output when the resource is saved.
func _on_resource_saved(resource: Resource) -> void:
	if not resource is WeaponData:
		return
	for error in (resource as WeaponData).validate():
		push_error("%s: %s" % [resource.resource_path, error])

func _build_native_extension() -> void:
	var platform := OS.get_name()
	if not NativeBuildConfig.is_platform_supported(platform):
		push_warning("Combat HitManager auto-build supports Windows and Linux; current platform is %s." % platform)
		return

	var project_root := ProjectSettings.globalize_path("res://")
	var native_dir := project_root.path_join("native/hit")
	var build_dir := NativeBuildConfig.build_directory(native_dir, platform)
	var lock_dir := build_dir.path_join(".editor-startup.lock")
	if not _acquire_build_lock(lock_dir):
		_load_native_extension()
		return
	var configured := false
	var configure_arguments := NativeBuildConfig.configure_arguments(native_dir, build_dir, platform)
	var local_cpp_source := OS.get_environment("GODOT_CPP_SOURCE_DIR")
	if local_cpp_source.is_empty():
		local_cpp_source = native_dir.path_join("godot-cpp")
	if DirAccess.dir_exists_absolute(local_cpp_source):
		configure_arguments.append("-DGODOT_CPP_SOURCE_DIR=" + local_cpp_source)

	configured = _run_cmake(configure_arguments, "configure")
	if configured:
		# An omitted job count becomes unbounded `make -j` on Linux. Limit a
		# first-build compiler fan-out to the processors available to this editor.
		configured = _run_cmake(["--build", build_dir, "--config", "Debug", "--parallel", str(maxi(1, OS.get_processor_count()))], "build")
	_release_build_lock(lock_dir)
	if configured:
		_load_native_extension()

func _acquire_build_lock(lock_dir: String) -> bool:
	var owner_path := lock_dir.path_join("owner_pid.txt")
	var started_msec := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_msec < 600000:
		var result := DirAccess.make_dir_absolute(lock_dir)
		if result == OK:
			var owner_file := FileAccess.open(owner_path, FileAccess.WRITE)
			if owner_file == null:
				DirAccess.remove_absolute(lock_dir)
				push_error("Could not write Combat HitManager build lock at %s." % lock_dir)
				return false
			owner_file.store_string(str(OS.get_process_id()))
			owner_file.close()
			return true
		if result != ERR_ALREADY_EXISTS:
			push_error("Could not create Combat HitManager build lock at %s (error %d)." % [lock_dir, result])
			return false
		if FileAccess.file_exists(owner_path):
			var owner_pid := FileAccess.get_file_as_string(owner_path).to_int()
			if owner_pid > 0 and not OS.is_process_running(owner_pid):
				DirAccess.remove_absolute(owner_path)
				DirAccess.remove_absolute(lock_dir)
				continue
		OS.delay_msec(250)
	push_error("Timed out waiting for another Godot editor to build the Combat HitManager.")
	return false

func _release_build_lock(lock_dir: String) -> void:
	DirAccess.remove_absolute(lock_dir.path_join("owner_pid.txt"))
	DirAccess.remove_absolute(lock_dir)

func _load_native_extension() -> void:
	var extension_path := "res://native/hit/hit_manager.gdextension"
	var project_root := ProjectSettings.globalize_path("res://")
	var library_path := NativeBuildConfig.expected_library_path(project_root, OS.get_name())
	if not FileAccess.file_exists(library_path):
		push_error("Combat HitManager build finished without producing %s." % library_path)
		return
	if GDExtensionManager.is_extension_loaded(extension_path):
		return
	var status := GDExtensionManager.load_extension(extension_path)
	if status != GDExtensionManager.LOAD_STATUS_OK:
		push_error("Combat HitManager GDExtension failed to load after CMake build (status %d)." % status)

func _run_cmake(arguments: PackedStringArray, step: String) -> bool:
	var output: Array = []
	var exit_code := OS.execute("cmake", arguments, output, true)
	var output_text: String = "\n".join(PackedStringArray(output))
	if exit_code != 0:
		push_error("Combat HitManager CMake %s failed (exit %d):\n%s" % [step, exit_code, output_text])
		return false
	if not output_text.is_empty():
		print("Combat HitManager CMake %s:\n%s" % [step, output_text])
	return true
