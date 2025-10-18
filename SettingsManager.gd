extends Node
class_name SettingsManager

# Manages application settings persistence

const CONFIG_PATH = "user://shadertoy_exporter_settings.cfg"

var config = ConfigFile.new()
var loading_settings: bool = false  # Flag to prevent signals during load
var save_timer: Timer = null

# Signals
signal settings_changed()

# UI References (set by main)
var url_input: TextEdit
var width_input: TextEdit
var height_input: TextEdit
var fps_input: TextEdit
var start_input: TextEdit
var duration_input: TextEdit
var mp4_checkbox: CheckBox
var gif_checkbox: CheckBox
var crf_input: TextEdit
var directory_path_label: Label

# Data
var selected_directory: String = ""

func _init():
	# Create debounce timer for auto-save
	save_timer = Timer.new()
	save_timer.wait_time = 0.5  # Wait 500ms after last change
	save_timer.one_shot = true
	save_timer.timeout.connect(_on_save_timer_timeout)
	add_child(save_timer)

func setup_ui_references(refs: Dictionary):
	"""Set up references to UI controls"""
	url_input = refs.get("url_input")
	width_input = refs.get("width_input")
	height_input = refs.get("height_input")
	fps_input = refs.get("fps_input")
	start_input = refs.get("start_input")
	duration_input = refs.get("duration_input")
	mp4_checkbox = refs.get("mp4_checkbox")
	gif_checkbox = refs.get("gif_checkbox")
	crf_input = refs.get("crf_input")
	directory_path_label = refs.get("directory_path_label")

func connect_change_signals():
	"""Connect all change signals for auto-save"""
	if url_input: url_input.text_changed.connect(_on_setting_changed)
	if width_input: width_input.text_changed.connect(_on_setting_changed)
	if height_input: height_input.text_changed.connect(_on_setting_changed)
	if fps_input: fps_input.text_changed.connect(_on_setting_changed)
	if start_input: start_input.text_changed.connect(_on_setting_changed)
	if duration_input: duration_input.text_changed.connect(_on_setting_changed)
	if mp4_checkbox: mp4_checkbox.toggled.connect(_on_setting_toggled)
	if gif_checkbox: gif_checkbox.toggled.connect(_on_setting_toggled)
	if crf_input: crf_input.text_changed.connect(_on_setting_changed)

func save_settings():
	"""Save all settings to config file"""
	# URL and frame settings
	if url_input: config.set_value("settings", "url", url_input.text)
	if width_input: config.set_value("settings", "width", width_input.text)
	if height_input: config.set_value("settings", "height", height_input.text)
	if fps_input: config.set_value("settings", "fps", fps_input.text)
	if start_input: config.set_value("settings", "start_time", start_input.text)
	if duration_input: config.set_value("settings", "duration", duration_input.text)

	# File settings
	config.set_value("settings", "output_directory", selected_directory)

	# Video settings
	if mp4_checkbox: config.set_value("settings", "mp4_enabled", mp4_checkbox.button_pressed)
	if gif_checkbox: config.set_value("settings", "gif_enabled", gif_checkbox.button_pressed)
	if crf_input: config.set_value("settings", "crf", crf_input.text)

	var err = config.save(CONFIG_PATH)
	if err != OK:
		push_error("Failed to save settings: " + str(err))
	else:
		print("Settings saved to: ", CONFIG_PATH)

func load_settings():
	"""Load all settings from config file"""
	var err = config.load(CONFIG_PATH)
	if err != OK:
		print("No existing settings found, using defaults")
		return

	# Set flag to prevent signals during load
	loading_settings = true

	# URL and frame settings
	if url_input: url_input.text = config.get_value("settings", "url", "")
	if width_input: width_input.text = config.get_value("settings", "width", "1920")
	if height_input: height_input.text = config.get_value("settings", "height", "1080")
	if fps_input: fps_input.text = config.get_value("settings", "fps", "60")
	if start_input: start_input.text = config.get_value("settings", "start_time", "0.0")
	if duration_input: duration_input.text = config.get_value("settings", "duration", "5.0")

	# File settings
	selected_directory = config.get_value("settings", "output_directory", "")
	if not selected_directory.is_empty() and directory_path_label:
		directory_path_label.text = selected_directory

	# Video settings
	if mp4_checkbox: mp4_checkbox.button_pressed = config.get_value("settings", "mp4_enabled", true)
	if gif_checkbox: gif_checkbox.button_pressed = config.get_value("settings", "gif_enabled", false)
	if crf_input: crf_input.text = config.get_value("settings", "crf", "18")

	print("Settings loaded from: ", CONFIG_PATH)

	# Clear flag after loading
	loading_settings = false

func set_directory(dir: String):
	"""Update the selected directory"""
	selected_directory = dir
	if directory_path_label:
		directory_path_label.text = dir
	save_settings()

func get_export_settings() -> Dictionary:
	"""Get current export settings as a dictionary"""
	return {
		"width": width_input.text.to_int() if width_input else 1920,
		"height": height_input.text.to_int() if height_input else 1080,
		"fps": fps_input.text.to_int() if fps_input else 60,
		"start_time": start_input.text.to_float() if start_input else 0.0,
		"duration": duration_input.text.to_float() if duration_input else 5.0,
		"crf": crf_input.text.to_int() if crf_input else 18,
		"mp4_enabled": mp4_checkbox.button_pressed if mp4_checkbox else true,
		"gif_enabled": gif_checkbox.button_pressed if gif_checkbox else false,
		"output_directory": selected_directory
	}

func _on_setting_changed(_new_text: String = ""):
	"""Handle setting text changes"""
	if loading_settings:
		return
	_restart_save_timer()

func _on_setting_toggled(_toggled: bool = false):
	"""Handle checkbox toggles"""
	if loading_settings:
		return
	_restart_save_timer()

func _restart_save_timer():
	"""Restart debounce timer"""
	if save_timer and not save_timer.is_stopped():
		save_timer.stop()
	if save_timer:
		save_timer.start()

func _on_save_timer_timeout():
	"""Timer expired - save settings now"""
	save_settings()
	settings_changed.emit()
