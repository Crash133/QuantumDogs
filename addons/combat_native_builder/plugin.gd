@tool
extends EditorPlugin

var _export_plugin: CombatNativeExportPlugin

func _enter_tree() -> void:
	resource_saved.connect(_on_resource_saved)
	_export_plugin = CombatNativeExportPlugin.new()
	add_export_plugin(_export_plugin)
	if build_native_extension(NativeBuildConfig.GODOT_CPP_TARGET):
		_load_native_extension()

func _exit_tree() -> void:
	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null

# Authoring check: weapon mistakes surface in Output when the resource is saved.
func _on_resource_saved(resource: Resource) -> void:
	if not resource is WeaponData:
		return
	for error in (resource as WeaponData).validate():
		push_error("%s: %s" % [resource.resource_path, error])

# Returns true when the library for `target` exists after a successful build.
static func build_native_extension(target: String) -> bool:
	var platform := OS.get_name()
	if not NativeBuildConfig.is_platform_supported(platform):
		push_warning("Combat HitManager auto-build supports Windows and Linux; current platform is %s." % platform)
		return false

	var project_root := ProjectSettings.globalize_path("res://")
	var native_dir := project_root.path_join("native/hit")
	var build_dir := NativeBuildConfig.build_directory(native_dir, platform, target)
	var lock_dir := build_dir.path_join(".editor-startup.lock")
	DirAccess.make_dir_recursive_absolute(build_dir)
	if not _acquire_build_lock(lock_dir):
		# Another editor holds the lock; use whatever library it already produced.
		return FileAccess.file_exists(NativeBuildConfig.expected_library_path(project_root, platform, target))
	var configure_arguments := NativeBuildConfig.configure_arguments(native_dir, build_dir, platform, target)
	var local_cpp_source := OS.get_environment("GODOT_CPP_SOURCE_DIR")
	if local_cpp_source.is_empty():
		local_cpp_source = native_dir.path_join("godot-cpp")
	if DirAccess.dir_exists_absolute(local_cpp_source):
		configure_arguments.append("-DGODOT_CPP_SOURCE_DIR=" + local_cpp_source)

	if _cache_is_from_other_checkout(build_dir, native_dir):
		configure_arguments.append("--fresh")

	var built := _run_cmake(configure_arguments, "configure")
	if built:
		# An omitted job count becomes unbounded `make -j` on Linux. Limit a
		# first-build compiler fan-out to the processors available to this editor.
		built = _run_cmake(["--build", build_dir, "--config", NativeBuildConfig.cmake_build_type(target), "--parallel", str(maxi(1, OS.get_processor_count()))], "build " + target)
	_release_build_lock(lock_dir)
	var library_path := NativeBuildConfig.expected_library_path(project_root, platform, target)
	if built and not FileAccess.file_exists(library_path):
		push_error("Combat HitManager build finished without producing %s." % library_path)
		return false
	return built

# A moved/copied checkout (or a WSL-made cache) makes CMake refuse to configure.
static func _cache_is_from_other_checkout(build_dir: String, native_dir: String) -> bool:
	var cache := FileAccess.get_file_as_string(build_dir.path_join("CMakeCache.txt"))
	for line in cache.split("\n"):
		if line.begins_with("CMAKE_HOME_DIRECTORY:INTERNAL="):
			var cached := line.get_slice("=", 1).strip_edges().simplify_path()
			var current := native_dir.simplify_path()
			# Windows paths are case-insensitive (c:/ vs C:/).
			return cached.to_lower() != current.to_lower() if OS.get_name() == "Windows" else cached != current
	return false

static func _acquire_build_lock(lock_dir: String) -> bool:
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

static func _release_build_lock(lock_dir: String) -> void:
	DirAccess.remove_absolute(lock_dir.path_join("owner_pid.txt"))
	DirAccess.remove_absolute(lock_dir)

func _load_native_extension() -> void:
	var extension_path := "res://native/hit/hit_manager.gdextension"
	if GDExtensionManager.is_extension_loaded(extension_path):
		return
	var status := GDExtensionManager.load_extension(extension_path)
	if status != GDExtensionManager.LOAD_STATUS_OK:
		push_error("Combat HitManager GDExtension failed to load after CMake build (status %d)." % status)

static func _run_cmake(arguments: PackedStringArray, step: String) -> bool:
	var output: Array = []
	var exit_code := OS.execute("cmake", arguments, output, true)
	var output_text: String = "\n".join(PackedStringArray(output))
	if exit_code != 0:
		push_error("Combat HitManager CMake %s failed (exit %d):\n%s" % [step, exit_code, output_text])
		return false
	if not output_text.is_empty():
		print("Combat HitManager CMake %s:\n%s" % [step, output_text])
	return true
