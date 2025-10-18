# Shadertoy Exporter

A Godot 4.5 application that exports Shadertoy shaders to high-quality video (MP4/GIF). Browse any shader on Shadertoy.com and export it at custom resolutions, framerates, and durations using frame-perfect capture with bundled ffmpeg.

## Features

- **Embedded Web Browser**: Navigate Shadertoy.com directly within the app
- **Frame-Perfect Capture**: Export shaders at exact frame timings for smooth playback
- **Custom Resolution & FPS**: Export at any resolution and framerate (e.g., 4K at 60fps)
- **Flexible Export Options**: Choose MP4, GIF, or both with configurable quality (CRF)
- **Time Control**: Specify start time and duration for your export
- **Settings Persistence**: Your preferences are automatically saved
- **Bundled FFmpeg**: Automatically includes platform-specific ffmpeg binaries
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **GitHub Actions Integration**: Automatic builds with bundled dependencies

## Quick Start

1. **Download the latest release** from the [Releases](https://github.com/YOUR_USERNAME/shadertoy-exporter/releases) page
2. **Extract and run** the executable for your platform
3. **Browse to a Shadertoy shader** (e.g., https://www.shadertoy.com/view/XsX3RB)
4. **Click "Open Shader"** to load it
5. **Configure your export settings** (resolution, FPS, duration, etc.)
6. **Select an output directory**
7. **Click "Export"** and wait for processing

## Building from Source

### Prerequisites

- Godot 4.5 or later
- [godot-wry](https://github.com/doceazedo/godot-wry) addon (included)
- FFmpeg (for local testing - bundled automatically in releases)

### Running Locally

```bash
# Open project in Godot
godot --path . --editor

# Or run directly
godot --path .
```

The app will use system-installed ffmpeg during development. For distribution, ffmpeg is automatically bundled via GitHub Actions.

## Usage Guide

### Export Settings

- **URL**: Paste any Shadertoy shader URL (e.g., `https://www.shadertoy.com/view/XsX3RB`)
- **Width/Height**: Output video resolution (e.g., 1920x1080, 3840x2160 for 4K)
- **FPS**: Frames per second (common values: 30, 60, 120)
- **Start Time**: When to begin capturing (in seconds)
- **Duration**: How long to capture (in seconds)
- **Output Directory**: Where to save exported files
- **Video Format**: Choose MP4, GIF, or both
- **CRF**: Video quality for MP4 (lower = better quality, 18-23 recommended)

### Tips

- **High Quality Exports**: Use 1920x1080 or 3840x2160 with CRF 18-20
- **Smooth Animations**: Export at 60 FPS for buttery smooth playback
- **File Organization**: Each shader exports to a subfolder named by its shader ID
- **GIF Limitations**: GIFs can have large file sizes; use shorter durations or lower resolutions
- **Preview Before Export**: Navigate the shader in the preview to find the best start time

### Troubleshooting

**Shader won't load**: Make sure you're on a `/view/` page, not the Shadertoy homepage

**Export fails**: Ensure you have write permissions to the output directory

**Video is choppy**: Increase FPS or reduce resolution

**FFmpeg not found**: The bundled version should work automatically; for development, install ffmpeg system-wide

## Project Structure

```
.
├── addons/
│   ├── godot_wry/            # WebView extension for embedded browser
│   └── ffmpeg/               # Platform-specific ffmpeg binaries
│       ├── linux/            # Linux x86_64 static binary
│       ├── windows/          # Windows x86_64 executable
│       └── macos/            # macOS universal binary
├── .github/
│   └── workflows/
│       └── godot-export.yml  # GitHub Actions for automated builds
├── ExportManager.gd          # Handles frame capture and video export
├── ShadertoyController.gd    # JavaScript injection and shader control
├── SettingsManager.gd        # Settings persistence
├── main.gd                   # Main UI controller
├── main.tscn                 # Main scene with UI layout
├── export_presets.cfg        # Export configuration for all platforms
└── project.godot             # Godot project configuration
```

## Automated Releases

This project uses GitHub Actions to automatically build releases with bundled ffmpeg for all platforms.

### Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow will automatically:
1. Download platform-specific ffmpeg binaries
2. Export the project for Linux, Windows, and macOS
3. Create a GitHub release with all builds

See [.github/README.md](.github/README.md) for detailed workflow documentation.

## How It Works

1. **WebView Integration**: Uses [godot-wry](https://github.com/doceazedo/godot-wry) to embed Chromium in Godot
2. **JavaScript Injection**: Injects custom JavaScript into Shadertoy pages to control rendering
3. **Frame Capture**: Hijacks the animation loop to render at precise frame timings
4. **WebGL Pixel Reading**: Reads pixels directly from WebGL context for lossless capture
5. **FFmpeg Encoding**: Compiles captured frames into video using bundled ffmpeg

## Dependencies

- **Godot 4.5**: Game engine and UI framework
- **godot-wry**: WebView extension for browser embedding
- **FFmpeg**: Video encoding (automatically bundled in releases)

## License

This project uses FFmpeg binaries which are licensed under LGPL 2.1 or later. The static builds used are compiled with LGPL-compatible options. For more information, see https://ffmpeg.org/legal.html

The Shadertoy Exporter application code is provided as-is for personal and educational use.
