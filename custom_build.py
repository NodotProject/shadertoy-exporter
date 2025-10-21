# custom_build.py - Optimized build profile for 2D games
target="template_release"
debug_symbols="no"
optimize="size_extra"  # Godot 4.5+ only, otherwise use "size"
lto="full"             # Full link-time optimization (slower build, smaller size)

# Disable 3D if you're making a 2D game
disable_3d="yes"
disable_advanced_gui="yes"

# Disable unnecessary features
deprecated="no"
vulkan="no"       # Using Compatibility renderer (OpenGL)
use_volk="no"
openxr="no"       # No VR/AR
minizip="no"      # No ZIP archive support
graphite="no"     # No SIL Graphite fonts

# Disable navigation if not needed
disable_navigation_2d="yes"
disable_navigation_3d="yes"
disable_xr="yes"

# Module configuration - disable all, enable only what you need
modules_enabled_by_default="no"
module_gdscript_enabled="yes"
module_text_server_fb_enabled="yes"  # Fallback text server (no RTL support)
module_freetype_enabled="yes"
module_svg_enabled="yes"
module_webp_enabled="no"
module_godot_physics_2d_enabled="no"  # Enable if you use 2D physics