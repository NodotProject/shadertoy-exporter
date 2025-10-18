extends Node
class_name ShadertoyController

# Handles Shadertoy-specific JavaScript injection and control

var webview: WebView
var is_shader_loaded: bool = false
var last_known_url: String = ""
var shader_id: String = ""
var url_monitor_timer: Timer = null

# Signals
signal shader_loaded()
signal shader_load_failed()
signal url_changed(new_url: String)

func _init():
	# Create timer for URL monitor re-injection
	url_monitor_timer = Timer.new()
	url_monitor_timer.wait_time = 2.0  # Check every 2 seconds
	url_monitor_timer.timeout.connect(_on_url_monitor_timer_timeout)
	add_child(url_monitor_timer)

func setup(webview_node: WebView):
	"""Initialize with webview reference"""
	webview = webview_node

func start_url_monitoring():
	"""Start monitoring for URL changes"""
	await get_tree().create_timer(1.0).timeout
	_inject_url_monitor()
	url_monitor_timer.start()

func load_shader(url: String) -> bool:
	"""Load a shader from URL and prepare it for export"""
	if url.is_empty():
		push_error("URL is empty")
		return false

	print("Loading shader: ", url)
	last_known_url = url
	shader_id = _extract_shader_id(url)

	if shader_id.is_empty():
		push_error("Could not extract shader ID from URL")
	else:
		print("Shader ID: ", shader_id)

	webview.load_url(url)
	is_shader_loaded = false

	# Wait for page to load and gShaderToy to be available
	var loaded = await _wait_for_shadertoy_ready()

	if loaded:
		_inject_shadertoy_controller()
		await get_tree().create_timer(0.5).timeout
		is_shader_loaded = true
		shader_loaded.emit()
		print("Shader loaded and ready for export")
		return true
	else:
		push_error("Failed to load Shadertoy - timed out waiting for page")
		is_shader_loaded = false
		shader_load_failed.emit()
		return false

func reconnect_to_shader() -> bool:
	"""Reconnect to currently loaded shader after navigation"""
	is_shader_loaded = false

	var loaded = await _wait_for_shadertoy_ready()

	if loaded:
		_inject_shadertoy_controller()
		await get_tree().create_timer(0.5).timeout
		is_shader_loaded = true
		shader_loaded.emit()
		print("Shader reconnected and ready for export")
		return true
	else:
		push_error("Failed to reconnect to shader")
		is_shader_loaded = false
		shader_load_failed.emit()
		return false

func reload_shader() -> bool:
	"""Reload the current shader URL to reset its state"""
	if last_known_url.is_empty():
		return false

	is_shader_loaded = false
	webview.load_url(last_known_url)

	var loaded = await _wait_for_shadertoy_ready()

	if loaded:
		_inject_shadertoy_controller()
		await get_tree().create_timer(0.5).timeout
		is_shader_loaded = true
		shader_loaded.emit()
		print("Shader reloaded and ready for export")
		return true
	else:
		push_error("Failed to reload shader")
		is_shader_loaded = false
		shader_load_failed.emit()
		return false

func handle_url_change(new_url: String):
	"""Handle URL change detected by monitor"""
	print("URL change detected: ", new_url, " (last known: ", last_known_url, ")")

	if new_url.contains("/view/"):
		# Navigated to a shader page
		if new_url != last_known_url:
			print("Detected navigation to shader: ", new_url)
			last_known_url = new_url
			shader_id = _extract_shader_id(new_url)

			if shader_id.is_empty():
				push_error("Could not extract shader ID from URL")
			else:
				print("Shader ID: ", shader_id)

			url_changed.emit(new_url)
			reconnect_to_shader.call_deferred()
		else:
			print("URL unchanged, skipping reconnection")
	else:
		# Navigated away from a shader page
		if last_known_url != "" and last_known_url.contains("/view/"):
			print("Navigated away from shader to: ", new_url)
			last_known_url = new_url
			shader_id = ""
			is_shader_loaded = false
			url_changed.emit(new_url)
		else:
			print("URL doesn't contain /view/, skipping reconnection")

func start_capture(fps: int, start_time: float, total_frames: int, width: int, height: int):
	"""Start frame capture with specified settings"""
	var js_setup = """
	(function() {
		var exporter = window.shadertoyExporter;

		// Resize canvas
		exporter.resizeCanvas(%d, %d);

		// Reset shader state
		gShaderToy.resetTime();
		gShaderToy.mTo = 0;

		// Start the capture loop
		exporter.startCapture(%d, %f, %d);
	})();
	""" % [width, height, fps, start_time, total_frames]
	eval_js(js_setup)
	print("Capture loop initiated")

func restore_shader_state():
	"""Restore shader to normal operation after export"""
	eval_js("window.shadertoyExporter.restore();")

# ============================================================================
# Private Methods
# ============================================================================

func _extract_shader_id(url: String) -> String:
	"""Extract shader ID from Shadertoy URL"""
	if url.contains("/view/"):
		var parts = url.split("/view/")
		if parts.size() >= 2:
			var id_part = parts[1].split("?")[0].split("#")[0]
			return id_part.strip_edges()
	return ""

func _wait_for_shadertoy_ready() -> bool:
	"""Poll for gShaderToy availability with timeout"""
	const MAX_RETRIES = 20  # 10 seconds total
	var retries = 0

	while retries < MAX_RETRIES:
		var check_js = """
		(function() {
			try {
				if (typeof gShaderToy !== 'undefined' && gShaderToy && gShaderToy.mCanvas) {
					window.ipc.postMessage(JSON.stringify({type: 'shadertoy_ready'}));
				} else {
					window.ipc.postMessage(JSON.stringify({type: 'shadertoy_not_ready'}));
				}
			} catch(e) {
				window.ipc.postMessage(JSON.stringify({type: 'shadertoy_not_ready'}));
			}
		})();
		"""
		eval_js(check_js)

		await get_tree().create_timer(0.5).timeout

		if is_shader_loaded:
			return true

		retries += 1

	return false

func _inject_url_monitor():
	"""Inject JavaScript to monitor URL changes"""
	var js_code = """
	(function() {
		if (window.shadertoyUrlMonitorInstalled) {
			return;
		}

		window.shadertoyUrlMonitorInstalled = true;
		var lastUrl = window.location.href;

		setInterval(function() {
			var currentUrl = window.location.href;
			if (currentUrl !== lastUrl) {
				console.log('URL changed from', lastUrl, 'to', currentUrl);
				lastUrl = currentUrl;
				if (window.ipc && window.ipc.postMessage) {
					window.ipc.postMessage(JSON.stringify({
						type: 'url_changed',
						url: currentUrl
					}));
				}
			}
		}, 500);

		console.log('URL monitor initialized for:', window.location.href);
	})();
	"""
	eval_js_deferred(js_code)

func _check_and_reinject_url_monitor():
	"""Check if monitor exists, and inject if it doesn't"""
	var check_js = """
	(function() {
		if (window.ipc && window.ipc.postMessage) {
			window.ipc.postMessage(JSON.stringify({
				type: 'url_monitor_status',
				installed: !!window.shadertoyUrlMonitorInstalled,
				currentUrl: window.location.href
			}));
		}
	})();
	"""
	eval_js(check_js)

func _on_url_monitor_timer_timeout():
	"""Periodic check for URL monitor"""
	_check_and_reinject_url_monitor()

func _inject_shadertoy_controller():
	"""Inject JavaScript controller for Shadertoy time and rendering"""
	var js_code = """
	(function() {
		if (typeof gShaderToy === 'undefined') {
			window.ipc.postMessage(JSON.stringify({
				type: 'error',
				message: 'gShaderToy not found - make sure you are on a Shadertoy shader page'
			}));
			return;
		}

		window.shadertoyExporter = {
			originalGetRealTime: null,
			originalRequestAnimationFrame: null,
			originalPaused: false,
			originalWidth: 0,
			originalHeight: 0,
			originalCanvasStyle: {},
			currentTime: 0,
			isOverridden: false,
			frameNumber: 0,
			totalFrames: 0,
			fps: 60,
			startTime: 0,
			captureInProgress: false,

			init: function() {
				this.originalGetRealTime = window.getRealTime;
				this.originalRequestAnimationFrame = gShaderToy.mEffect.RequestAnimationFrame;
				this.originalPaused = gShaderToy.mIsPaused;
				this.originalWidth = gShaderToy.mCanvas.width;
				this.originalHeight = gShaderToy.mCanvas.height;

				var canvas = gShaderToy.mCanvas;
				this.originalCanvasStyle = {
					display: canvas.style.display,
					visibility: canvas.style.visibility,
					opacity: canvas.style.opacity
				};

				console.log('Shadertoy Exporter initialized');
			},

			startCapture: function(fps, startTime, totalFrames) {
				if (this.isOverridden) return;

				this.fps = fps;
				this.startTime = startTime;
				this.totalFrames = totalFrames;
				this.frameNumber = 0;
				this.captureInProgress = false;

				var self = this;

				window.getRealTime = function() {
					return self.currentTime;
				};

				if (gShaderToy.mIsPaused) {
					gShaderToy.pauseTime();
				}

				gShaderToy.mEffect.RequestAnimationFrame = function(originalRender) {
					if (self.frameNumber >= self.totalFrames) {
						window.ipc.postMessage(JSON.stringify({type: 'export_complete'}));
						return;
					}

					window.requestAnimationFrame(function() {
						if (self.frameNumber >= self.totalFrames) {
							window.ipc.postMessage(JSON.stringify({type: 'export_complete'}));
							return;
						}

						self.currentTime = (self.startTime + self.frameNumber / self.fps) * 1000;
						originalRender();
						self.captureFrameSync(self.frameNumber);
						self.frameNumber++;
					});
				};

				this.isOverridden = true;
				console.log('Capture loop started');
			},

			captureFrameSync: function(frameNumber) {
				var self = this;
				var canvas = gShaderToy.mCanvas;
				canvas.style.display = '';
				canvas.style.visibility = 'visible';
				canvas.style.opacity = '1';

				// Get WebGL context and read pixels directly (Shadertoy uses WebGL, not 2D canvas)
				var gl = canvas.getContext('webgl') || canvas.getContext('webgl2') || canvas.getContext('experimental-webgl');
				if (!gl) {
					console.error('Failed to get WebGL context');
					return;
				}

				var width = canvas.width;
				var height = canvas.height;
				var pixels = new Uint8Array(width * height * 4);

				// Read pixels from WebGL
				gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);

				// Flip Y axis (WebGL origin is bottom-left, PNG origin is top-left)
				var flippedPixels = new Uint8Array(width * height * 4);
				for (var y = 0; y < height; y++) {
					for (var x = 0; x < width; x++) {
						var srcIdx = (y * width + x) * 4;
						var dstIdx = ((height - 1 - y) * width + x) * 4;
						flippedPixels[dstIdx] = pixels[srcIdx];
						flippedPixels[dstIdx + 1] = pixels[srcIdx + 1];
						flippedPixels[dstIdx + 2] = pixels[srcIdx + 2];
						flippedPixels[dstIdx + 3] = pixels[srcIdx + 3];
					}
				}

				// Convert to base64
				var binary = '';
				var len = flippedPixels.byteLength;
				for (var i = 0; i < len; i++) {
					binary += String.fromCharCode(flippedPixels[i]);
				}
				var base64 = btoa(binary);

				window.ipc.postMessage(JSON.stringify({
					type: 'frame_data',
					frameNumber: frameNumber,
					width: width,
					height: height,
					data: base64
				}));
			},

			restore: function() {
				if (!this.isOverridden) return;

				window.getRealTime = this.originalGetRealTime;
				gShaderToy.mEffect.RequestAnimationFrame = this.originalRequestAnimationFrame;

				if (gShaderToy.mCanvas.width !== this.originalWidth ||
					gShaderToy.mCanvas.height !== this.originalHeight) {
					this.resizeCanvas(this.originalWidth, this.originalHeight);
				}

				var canvas = gShaderToy.mCanvas;
				canvas.style.display = this.originalCanvasStyle.display || '';
				canvas.style.visibility = this.originalCanvasStyle.visibility || '';
				canvas.style.opacity = this.originalCanvasStyle.opacity || '';

				if (!this.originalPaused && gShaderToy.mIsPaused) {
					gShaderToy.pauseTime();
				}
				if (this.originalPaused && !gShaderToy.mIsPaused) {
					gShaderToy.pauseTime();
				}

				this.isOverridden = false;
				console.log('Original state restored');
			},

			resizeCanvas: function(width, height) {
				gShaderToy.mCanvas.width = width;
				gShaderToy.mCanvas.height = height;
				gShaderToy.mEffect.mXres = width;
				gShaderToy.mEffect.mYres = height;
				gShaderToy.mEffect.ResizeBuffers(width, height);
			}
		};

		window.shadertoyExporter.init();
		console.log('Shadertoy controller injected successfully');
	})();
	"""
	eval_js(js_code)

# ============================================================================
# JavaScript Helper Methods
# ============================================================================

func eval_js(javascript: String) -> void:
	"""Execute JavaScript in the webview"""
	if webview:
		webview.eval(javascript)
	else:
		push_error("WebView node not found")

func eval_js_deferred(javascript: String) -> void:
	"""Execute JavaScript deferred to avoid borrow conflicts"""
	if webview:
		webview.eval.call_deferred(javascript)
	else:
		push_error("WebView node not found")
