# 3D Viewer for macOS

A native macOS app for previewing and inspecting 3D models. Built with
**SwiftUI + SceneKit** in a single Swift Package — no third-party dependencies.
Drop a file in the window and it shows up.

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

### Loading
- Drag-and-drop a supported file onto the window
- Open via `⌘O`, the file picker, or **Open Recent** (last 10 files)
- Open from Finder / the Dock once bundled as a `.app` (see below)
- Auto-frames the camera to fit the model's bounding sphere

### Viewing
- Orbit / pan / zoom (powered by SceneKit)
- **Display modes** — Shaded, Wireframe, Shaded + Wireframe, Points
- **Lighting presets** — Studio (3-point), Outdoor, Single Key, or an
  image-based **Environment** (load your own HDR/EXR/JPG/PNG)
- **Backgrounds** — Dark, Light, Checkerboard, or the environment image
- **Overlays** — bounding box, wireframe overlay, axes gizmo, vertex normals
- **Camera list** — switch between the auto camera and any cameras baked
  into the file
- **Reset camera** (`⌘R`)

### Animation
- Play / pause and scrub any animations contained in the file
  (`.dae`, `.usdz`, `.abc`, …) with a timeline slider

### Inspection
- Per-mesh list with visibility toggles, material summaries, and color swatches
- Statistics: node / mesh / vertex / triangle counts, surface area, volume
- **Measurement tool** — click two surface points to measure distance

### Export & capture
- Save a PNG snapshot (`⌘S`) or copy it to the clipboard (`⇧⌘C`)
- Export the model as `.scn` or `.usdz`
- Export a turntable animation as an animated **GIF**

### Quick Look
- A Quick Look preview extension for Finder/Spotlight lives in
  [`QuickLookExtension/`](QuickLookExtension/) — see its README (it needs an
  Xcode project, since SwiftPM can't build app extensions)

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

> glTF (`.gltf` / `.glb`) is intentionally not supported — SceneKit has no
> built-in loader and adding one would require a third-party dependency.

## Requirements

- macOS 13 Ventura or later
- Swift 5.9 toolchain (Xcode 15+ or matching command-line tools)

## Quick start

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
| Reset camera | `⌘R` |
| Save snapshot | `⌘S` |
| Copy snapshot | `⇧⌘C` |
| Close current model | `⇧⌘W` |
| Measure | Toggle *Measurement Mode* in the inspector, then click two points |

## Build a `.app` bundle

The package builds a plain executable. To produce a double-clickable app that
also opens files from Finder and the Dock:

```bash
swift build -c release

APP="ThreeDViewer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ThreeDViewer "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ThreeDViewer</string>
  <key>CFBundleIdentifier</key><string>local.ThreeDViewer</string>
  <key>CFBundleName</key><string>3D Viewer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>3D Model</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>public.geometry-definition-format</string>
      <string>public.polygon-file-format</string>
      <string>public.standard-tesselated-geometry-format</string>
      <string>com.pixar.universal-scene-description</string>
      <string>com.pixar.universal-scene-description-mobile</string>
      <string>public.scenekit.scene</string>
      <string>org.khronos.collada.digital-asset-exchange</string>
      <string>public.alembic</string>
    </array>
  </dict></array>
</dict></plist>
PLIST

open "$APP"
```

## Project layout

```
.
├── Package.swift
├── Sources/
│   └── ThreeDViewer/
│       ├── ThreeDViewerApp.swift   # @main, AppDelegate, menu commands
│       ├── ContentView.swift       # split view, toolbar, drop zone, playback bar
│       ├── Inspector.swift         # sidebar: display, lighting, meshes, stats
│       ├── ViewerState.swift       # observable app state, loading, export
│       ├── SceneViewport.swift     # SCNView wrapper: camera, measurement, GIF
│       ├── SceneHelpers.swift      # framing, lighting rigs, axes, normals
│       └── GeometryAnalysis.swift  # vertex/triangle counts, area, volume
└── QuickLookExtension/             # Finder/Spotlight preview (needs Xcode)
```

## How it works

- `SCNScene(url:options:)` handles the SceneKit-native formats; `MDLAsset`
  (Model I/O) loads `.obj`, `.ply`, and `.stl`, bridged in via `SCNScene(mdlAsset:)`.
- After loading, a camera node is placed at `~2.8 ×` the model's bounding-sphere
  radius so the model fills the viewport regardless of scale.
- All viewer-added nodes (camera, lights, axes, normals, measurement markers)
  are namespaced with a `__viewer_` prefix so they're excluded from statistics
  and from exported files.
- Surface area is the sum of triangle areas; volume is the absolute value of the
  summed signed tetrahedron volumes (accurate for closed meshes).
- Turntable GIFs are rendered by orbiting the camera and writing
  `SCNView.snapshot()` frames through ImageIO — no dependencies.

## Contributing

Issues and pull requests are welcome. Keep changes small and focused — this is
meant to stay a single-binary, dependency-free utility.

## License

MIT — see [LICENSE](LICENSE).
