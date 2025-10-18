extends HBoxContainer

# Main UI controller - coordinates between managers and UI

# Managers
var settings_manager: SettingsManager
var shadertoy_controller: ShadertoyController
var export_manager: ExportManager

# WebView and UI Node References
@onready var webview = $ShaderPreviewContainer/WebView

# URL Controls
@onready var url_input = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/URLContainer/URLInput
@onready var open_button = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/OpenShaderButton

# Frame Settings
@onready var width_input = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/FrameSettingsContainer/FrameSettingsGrid/WidthInput
@onready var height_input = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/FrameSettingsContainer/FrameSettingsGrid/HeightInput
@onready var fps_input = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/FrameSettingsContainer/FrameSettingsGrid/FPSInput
@onready var start_input = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/FrameSettingsContainer/FrameSettingsGrid/StartInput
@onready var duration_input = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/FrameSettingsContainer/FrameSettingsGrid/DurationInput

# File Settings
@onready var select_directory_button = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/SelectDirectoryButton
@onready var directory_dialog = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/DirectoryDialog
@onready var directory_path_label = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/FileSettingsGrid/DirectoryPathLabel

# Video Settings
@onready var mp4_checkbox = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/VideoFormatContainer/MP4CheckBox
@onready var gif_checkbox = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/VideoFormatContainer/GIFCheckBox
@onready var crf_input = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/CRFInput

# Export Button
@onready var export_button = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/ExportButton

# Progress UI
@onready var status_label = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/StatusLabel
@onready var progress_bar = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/ProgressBar
@onready var progress_label = $ControlPanel/ScrollContainer/MarginContainer/SettingsContainer/ProgressLabel

func _ready():
	# Create managers
	_setup_managers()

	# Connect UI signals
	_connect_ui_signals()

	# Initialize UI state
	export_button.disabled = true
	progress_bar.value = 0
	progress_label.text = ""

	# Load settings
	settings_manager.load_settings()

	# Start URL monitoring
	shadertoy_controller.start_url_monitoring()

	print("Shadertoy Exporter initialized")

func _setup_managers():
	"""Create and configure all managers"""
	# Settings Manager
	settings_manager = SettingsManager.new()
	add_child(settings_manager)
	settings_manager.setup_ui_references({
		"url_input": url_input,
		"width_input": width_input,
		"height_input": height_input,
		"fps_input": fps_input,
		"start_input": start_input,
		"duration_input": duration_input,
		"mp4_checkbox": mp4_checkbox,
		"gif_checkbox": gif_checkbox,
		"crf_input": crf_input,
		"directory_path_label": directory_path_label
	})
	settings_manager.connect_change_signals()

	# Shadertoy Controller
	shadertoy_controller = ShadertoyController.new()
	add_child(shadertoy_controller)
	shadertoy_controller.setup(webview)
	shadertoy_controller.shader_loaded.connect(_on_shader_loaded)
	shadertoy_controller.shader_load_failed.connect(_on_shader_load_failed)
	shadertoy_controller.url_changed.connect(_on_url_changed)

	# Export Manager
	export_manager = ExportManager.new()
	add_child(export_manager)
	export_manager.setup(shadertoy_controller, settings_manager)
	export_manager.export_started.connect(_on_export_started)
	export_manager.export_progress.connect(_on_export_progress)
	export_manager.export_complete.connect(_on_export_complete)
	export_manager.export_cancelled.connect(_on_export_cancelled)
	export_manager.status_changed.connect(_on_status_changed)

func _connect_ui_signals():
	"""Connect all UI element signals"""
	open_button.pressed.connect(_on_open_shader_pressed)
	export_button.pressed.connect(_on_export_pressed)
	directory_dialog.dir_selected.connect(_on_directory_selected)
	webview.ipc_message.connect(_on_webview_ipc_message)

# ============================================================================
# UI Signal Handlers
# ============================================================================

func _on_open_shader_pressed():
	"""Handle Open Shader button press"""
	var url = url_input.text.strip_edges()
	if url.is_empty():
		push_error("URL is empty")
		return

	_update_status("Loading shader...")
	export_button.disabled = true

	var success = await shadertoy_controller.load_shader(url)
	if not success:
		_update_status("Error: Failed to load shader")

func _on_export_pressed():
	"""Handle Export/Cancel button press"""
	if export_manager.is_exporting:
		export_manager.cancel_export()
	else:
		export_manager.start_export()

func _on_directory_selected(dir: String):
	"""Handle directory selection"""
	settings_manager.set_directory(dir)
	print("Output directory selected: ", dir)

# ============================================================================
# Manager Signal Handlers
# ============================================================================

func _on_shader_loaded():
	"""Handle successful shader load"""
	export_button.disabled = false
	_update_status("Shader loaded - Ready to export")

func _on_shader_load_failed():
	"""Handle failed shader load"""
	export_button.disabled = true
	_update_status("Error: Failed to load shader")

func _on_url_changed(new_url: String):
	"""Handle URL change from browser navigation"""
	if new_url.contains("/view/"):
		_update_status("Reconnecting to shader...")
	else:
		export_button.disabled = true
		_update_status("No shader loaded")

func _on_export_started():
	"""Handle export start"""
	export_button.text = "Cancel"
	_disable_ui_during_export(true)

func _on_export_progress(current: int, total: int):
	"""Handle export progress update"""
	_update_progress(current, total)

func _on_export_complete():
	"""Handle export completion"""
	export_button.text = "Export"
	_disable_ui_during_export(false)

	# Reload shader after export
	if shadertoy_controller.last_known_url.contains("/view/"):
		print("Reloading shader after export")
		shadertoy_controller.reload_shader()

func _on_export_cancelled():
	"""Handle export cancellation"""
	export_button.text = "Export"
	_disable_ui_during_export(false)

func _on_status_changed(message: String):
	"""Handle status message changes"""
	_update_status(message)

# ============================================================================
# WebView IPC Message Handler
# ============================================================================

func _on_webview_ipc_message(message: String):
	"""Handle IPC messages from webview JavaScript"""
	var data = JSON.parse_string(message)
	if data == null:
		return

	match data.get("type", ""):
		"frame_data":
			var frame_number = data.get("frameNumber", -1)
			var base64_data = data.get("data", "")
			var width = data.get("width", 0)
			var height = data.get("height", 0)
			export_manager.handle_frame_data(frame_number, base64_data, width, height)

		"export_complete":
			export_manager.finish_export()

		"shadertoy_ready":
			shadertoy_controller.is_shader_loaded = true

		"shadertoy_not_ready":
			# Still waiting for gShaderToy
			pass

		"url_changed":
			shadertoy_controller.handle_url_change(data.get("url", ""))

		"url_monitor_status":
			var installed = data.get("installed", false)
			var current_url = data.get("currentUrl", "")
			if not installed:
				print("URL monitor not installed, re-injecting...")
				shadertoy_controller._inject_url_monitor()
				# Check if URL changed while monitor was missing
				if current_url != "" and current_url != shadertoy_controller.last_known_url:
					print("Detected missed URL change to: ", current_url)
					shadertoy_controller.handle_url_change(current_url)

		"error":
			push_error("JS Error: " + str(data.get("message", "Unknown error")))

# ============================================================================
# UI Helper Methods
# ============================================================================

func _update_status(message: String):
	"""Update status label"""
	status_label.text = message

func _update_progress(current: int, total: int):
	"""Update progress bar and label"""
	if total > 0:
		progress_bar.value = float(current) / float(total)
		progress_label.text = "Frame %d / %d" % [current, total]
	else:
		progress_bar.value = 0
		progress_label.text = ""

func _disable_ui_during_export(disabled: bool):
	"""Disable/enable UI controls during export"""
	open_button.disabled = disabled
	width_input.editable = !disabled
	height_input.editable = !disabled
	fps_input.editable = !disabled
	start_input.editable = !disabled
	duration_input.editable = !disabled
	select_directory_button.disabled = disabled
	mp4_checkbox.disabled = disabled
	gif_checkbox.disabled = disabled
	crf_input.editable = !disabled
