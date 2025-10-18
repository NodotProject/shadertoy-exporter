extends Node
class_name ExportManager

# Handles frame capture and video compilation

const FRAME_PREFIX = "frame_"

var is_exporting: bool = false
var current_frame: int = 0
var total_frames: int = 0
var captured_frames: Array = []
var pending_writes: int = 0

# References
var shadertoy_controller: ShadertoyController
var settings_manager: SettingsManager

# Signals
signal export_started
signal export_progress(current: int, total: int)
signal export_complete
signal export_cancelled
signal status_changed(message: String)

func setup(controller: ShadertoyController, settings: SettingsManager):
	"""Initialize with required managers"""
	shadertoy_controller = controller
	settings_manager = settings

func start_export() -> bool:
	"""Start the export process"""
	if is_exporting:
		return false

	# Validate settings
	var export_settings = settings_manager.get_export_settings()
	if not _validate_settings(export_settings):
		return false

	is_exporting = true
	current_frame = 0
	captured_frames.clear()

	# Calculate total frames
	total_frames = int(export_settings.duration * export_settings.fps)

	print("Starting export: %d frames at %dx%d @ %d fps" % [
		total_frames,
		export_settings.width,
		export_settings.height,
		export_settings.fps
	])

	export_started.emit()
	status_changed.emit("Capturing frames...")
	export_progress.emit(0, total_frames)

	# Start capture
	shadertoy_controller.start_capture(
		export_settings.fps,
		export_settings.start_time,
		total_frames,
		export_settings.width,
		export_settings.height
	)

	return true

func cancel_export():
	"""Cancel the current export"""
	print("Export cancelled by user")
	status_changed.emit("Export cancelled")
	shadertoy_controller.restore_shader_state()
	_cleanup()
	export_cancelled.emit()

func handle_frame_data(frame_number: int, base64_data: String, width: int = 0, height: int = 0):
	"""Process received frame data"""
	if frame_number < 0 or base64_data.is_empty():
		push_error("Invalid frame data received")
		status_changed.emit("Error: Invalid frame data")
		return

	# Decode base64 to bytes
	var image_data = Marshalls.base64_to_raw(base64_data)

	# Create Image from raw RGBA data (new format) or PNG data (legacy)
	var image: Image
	if width > 0 and height > 0:
		# New format: raw RGBA pixel data
		image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, image_data)
	else:
		# Legacy format: PNG data
		image = Image.new()
		var err = image.load_png_from_buffer(image_data)
		if err != OK:
			push_error("Failed to load PNG from buffer")
			status_changed.emit("Error: Failed to decode frame data")
			cancel_export()
			return

	# Determine output directory
	var output_dir = _get_output_directory()
	if output_dir.is_empty():
		push_error("Failed to determine output directory")
		cancel_export()
		return

	# Save PNG file on background thread
	var filename = "%s%04d.png" % [FRAME_PREFIX, frame_number]
	var filepath = output_dir.path_join(filename)

	# Queue write on background thread
	pending_writes += 1
	WorkerThreadPool.add_task(_save_frame_threaded.bind(image, filepath, frame_number))

func finish_export():
	"""Complete the export process"""
	print("Frame capture complete!")
	status_changed.emit("Frame capture complete!")

	# Wait for all pending frame writes to complete
	while pending_writes > 0:
		status_changed.emit("Waiting for %d frames to finish writing..." % pending_writes)
		await get_tree().process_frame

	print("All frames written to disk")
	status_changed.emit("All frames written to disk")

	# Restore shader state
	shadertoy_controller.restore_shader_state()

	# Compile video if requested
	var export_settings = settings_manager.get_export_settings()
	if export_settings.mp4_enabled or export_settings.gif_enabled:
		await _compile_video()
	else:
		_cleanup()
		export_complete.emit()

# ============================================================================
# Private Methods
# ============================================================================

func _validate_settings(settings: Dictionary) -> bool:
	"""Validate export settings"""
	if settings.output_directory.is_empty():
		push_error("Please select an output directory")
		return false

	if settings.width <= 0 or settings.height <= 0:
		push_error("Width and height must be positive")
		return false

	if settings.fps <= 0:
		push_error("FPS must be positive")
		return false

	if settings.duration <= 0:
		push_error("Duration must be positive")
		return false

	if not shadertoy_controller.is_shader_loaded:
		push_error("Please load a shader first")
		return false

	return true

func _get_output_directory() -> String:
	"""Get the output directory (with shader ID subfolder if available)"""
	var base_dir = settings_manager.selected_directory
	var shader_id = shadertoy_controller.shader_id

	if shader_id.is_empty():
		return base_dir

	var output_dir = base_dir.path_join(shader_id)

	# Create shader ID subfolder if it doesn't exist
	if not DirAccess.dir_exists_absolute(output_dir):
		var err = DirAccess.make_dir_absolute(output_dir)
		if err != OK:
			push_error("Failed to create shader directory: " + output_dir)
			return ""
		else:
			print("Created shader directory: ", output_dir)

	return output_dir

func _get_ffmpeg_path() -> String:
	"""Get path to bundled ffmpeg binary, falls back to system ffmpeg if not found"""
	var os_name = OS.get_name()
	var ffmpeg_path = ""

	match os_name:
		"Windows":
			ffmpeg_path = "res://addons/ffmpeg/windows/ffmpeg.exe"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			ffmpeg_path = "res://addons/ffmpeg/linux/ffmpeg"
		"macOS":
			ffmpeg_path = "res://addons/ffmpeg/macos/ffmpeg"
		_:
			push_warning("Unsupported platform: " + os_name + ", falling back to system ffmpeg")
			return "ffmpeg"

	# Convert res:// path to absolute path for OS.execute
	var absolute_path = ProjectSettings.globalize_path(ffmpeg_path)

	# Check if bundled ffmpeg exists
	if FileAccess.file_exists(absolute_path):
		print("Using bundled ffmpeg: ", absolute_path)
		return absolute_path
	else:
		push_warning("Bundled ffmpeg not found at: " + absolute_path + ", falling back to system ffmpeg")
		return "ffmpeg"

func _compile_video():
	"""Compile captured frames into video"""
	print("Compiling video with ffmpeg...")
	status_changed.emit("Preparing video encoding...")
	await get_tree().process_frame

	var export_settings = settings_manager.get_export_settings()
	var target_dir = _get_output_directory()

	if target_dir.is_empty():
		push_error("Failed to determine output directory")
		_cleanup()
		return

	var input_pattern = target_dir.path_join("%s%%04d.png" % FRAME_PREFIX)
	var video_created = false

	# Compile MP4
	if export_settings.mp4_enabled:
		status_changed.emit("Encoding MP4 (this may take a while)...")
		await get_tree().process_frame

		var output_mp4 = target_dir.path_join("output.mp4")
		var mp4_args = [
			"-y",
			"-framerate", str(export_settings.fps),
			"-i", input_pattern,
			"-c:v", "libx264",
			"-crf", str(export_settings.crf),
			"-pix_fmt", "yuv420p",
			output_mp4
		]

		var ffmpeg_path = _get_ffmpeg_path()
		print("Running ffmpeg for MP4...")
		print("Command: %s %s" % [ffmpeg_path, " ".join(mp4_args)])
		var output: Array = []
		var mp4_result = OS.execute(ffmpeg_path, mp4_args, output, true)
		if mp4_result == 0:
			print("MP4 created: ", output_mp4)
			video_created = true
		else:
			var error_msg = "ffmpeg failed for MP4 with exit code %d" % mp4_result
			if output.size() > 0:
				error_msg += "\nOutput: " + "\n".join(output)
			push_error(error_msg)
			status_changed.emit("Error: ffmpeg failed for MP4 (code %d)" % mp4_result)

	# Compile GIF
	if export_settings.gif_enabled:
		status_changed.emit("Encoding GIF (this may take a while)...")
		await get_tree().process_frame

		var output_gif = target_dir.path_join("output.gif")
		var gif_args = [
			"-y",
			"-framerate", str(export_settings.fps),
			"-i", input_pattern,
			"-vf", "fps=%d,scale=1920:-1:flags=lanczos" % export_settings.fps,
			output_gif
		]

		var ffmpeg_path = _get_ffmpeg_path()
		print("Running ffmpeg for GIF...")
		print("Command: %s %s" % [ffmpeg_path, " ".join(gif_args)])
		var output: Array = []
		var gif_result = OS.execute(ffmpeg_path, gif_args, output, true)
		if gif_result == 0:
			print("GIF created: ", output_gif)
			video_created = true
		else:
			var error_msg = "ffmpeg failed for GIF with exit code %d" % gif_result
			if output.size() > 0:
				error_msg += "\nOutput: " + "\n".join(output)
			push_error(error_msg)
			status_changed.emit("Error: ffmpeg failed for GIF (code %d)" % gif_result)

	# Delete PNG frames after successful video creation
	if video_created:
		status_changed.emit("Cleaning up PNG frames...")
		await get_tree().process_frame
		_delete_png_frames(target_dir)

	_cleanup()
	export_complete.emit()

func _save_frame_threaded(image: Image, filepath: String, frame_number: int):
	"""Save frame on background thread"""
	var err = image.save_png(filepath)
	call_deferred("_on_frame_saved", err, filepath, frame_number)

func _on_frame_saved(err: int, filepath: String, frame_number: int):
	"""Handle frame save completion on main thread"""
	pending_writes -= 1

	if err != OK:
		push_error("Failed to save frame: " + filepath)
		status_changed.emit("Error: Failed to save frame")
		cancel_export()
		return

	print("Saved: ", filepath)

	# Update progress
	current_frame = frame_number + 1
	export_progress.emit(current_frame, total_frames)

func _delete_png_frames(directory: String):
	"""Delete PNG frame files from directory"""
	print("Deleting PNG frames from: ", directory)
	var dir = DirAccess.open(directory)
	if dir:
		var deleted_count = 0
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.begins_with(FRAME_PREFIX) and file_name.ends_with(".png"):
				var full_path = directory.path_join(file_name)
				var err = dir.remove(full_path)
				if err == OK:
					deleted_count += 1
				else:
					push_error("Failed to delete frame: " + full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
		print("Deleted %d PNG frames" % deleted_count)
	else:
		push_error("Could not open directory for cleanup: " + directory)

func _cleanup():
	"""Clean up export state"""
	is_exporting = false
	status_changed.emit("Export complete!")
	print("Export complete!")
