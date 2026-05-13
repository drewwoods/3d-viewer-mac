# 3D Viewer for macOS

A tiny, native macOS app for previewing 3D models. Built with **SwiftUI + SceneKit** in a single Swift Package — no dependencies. Drop a file in the window and it shows up.

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- Drag-and-drop any supported 3D file onto the window
- Auto-frames the camera to fit the model's bounding sphere
- Built-in orbit / pan / zoom (powered by SceneKit)
- Reports node, vertex, and triangle counts
- Open file panel (`⌘O`) and quick close (`⇧⌘W`)
- Zero third-party dependencies

## Supported formats

| Format | Extensions | Loader |
|--------|------------|--------|
| Wavefront OBJ | `.obj` | Model I/O |
| Universal Scene Description | `.usdz`, `.usd`, `.usda`, `.usdc` | SceneKit |
| Collada | `.dae` | SceneKit |
| SceneKit archive | `.scn` | SceneKit |
| Stanford PLY | `.ply` | Model I/O |
| STL | `.stl` | Model I/O |
| Alembic | `.abc` | SceneKit |

## Requirements

- macOS 13 Ventura or later
- Swift 5.9 toolchain (Xcode 15+ or the matching command-line tools)

## Quick start

Clone and run:

```bash
git clone https://github.com/moerdowo/3d-viewer-mac.git
cd 3d-viewer-mac
swift run
```

Or open the package in Xcode:

```bash
open Package.swift
```

## Controls

| Action | Gesture / Shortcut |
|--------|--------------------|
| Load a model | Drag a file onto the window, or `⌘O` |
| Orbit camera | Left-click + drag |
| Pan camera | Right-click + drag, or two-finger drag |
| Zoom | Scroll wheel, or pinch |
| Close current model | `⇧⌘W` |

## Build a `.app` bundle

The package builds a plain executable. To produce a double-clickable app:

```bash
swift build -c release

APP="ThreeDViewer.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ThreeDViewer "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ThreeDViewer</string>
  <key>CFBundleIdentifier</key><string>local.ThreeDViewer</string>
  <key>CFBundleName</key><string>3D Viewer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

open "$APP"
```

## Project layout

```
.
├── Package.swift
└── Sources/
    └── ThreeDViewer/
        ├── ThreeDViewerApp.swift   # @main entry + menu commands
        ├── ContentView.swift       # SceneView, drop zone, top bar
        └── ViewerState.swift       # File loading, framing, statistics
```

## How it works

- `SCNScene(url:options:)` handles the SceneKit-native formats directly.
- `MDLAsset` (Model I/O) loads `.obj`, `.ply`, and `.stl`, then is bridged into a `SCNScene` via `SCNScene(mdlAsset:)`.
- After loading, a camera node is inserted whose distance is `~2.6 ×` the model's bounding-sphere radius, so the model fills the viewport regardless of scale.
- SceneKit's `.allowsCameraControl` provides orbit/pan/zoom for free; `.autoenablesDefaultLighting` gives a neutral 3-point light setup.

## Contributing

Issues and pull requests are welcome. Keep changes small and focused — this is meant to stay a single-binary, dependency-free utility.

## License

MIT — see [LICENSE](LICENSE).
