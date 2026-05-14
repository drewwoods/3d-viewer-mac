# Quick Look Preview Extension

This folder contains a Quick Look extension that renders 3D model files directly
in Finder (spacebar preview), the Get Info panel, and Spotlight.

## Why it isn't in the SwiftPM build

Swift Package Manager **cannot build app extensions** — they must be embedded in
a host `.app` bundle, which requires an Xcode project. The main viewer ships as a
SwiftPM executable, so the extension lives here as drop-in source you add to an
Xcode project.

## Setup

1. Create (or open) an Xcode project for the host app — see the "Build a `.app`
   bundle" section of the root `README.md`, or make a new macOS App project and
   add the files from `Sources/ThreeDViewer/` to it.
2. **File ▸ New ▸ Target… ▸ Quick Look Preview Extension.** Name it e.g.
   `ThreeDViewerQuickLook`.
3. Delete the auto-generated `PreviewViewController.swift` and storyboard from the
   new target. Add `QuickLookExtension/PreviewViewController.swift` to the
   extension target instead.
4. Replace the new target's generated `Info.plist` contents with
   `QuickLookExtension/Info.plist` (or merge the `NSExtension` dict).
5. In the extension target's **General ▸ Deployment Info**, set macOS 13.0+.
6. Make sure the extension target links **SceneKit** and **ModelIO**.
7. Build and run the host app once so macOS registers the embedded extension.

## Supported types

OBJ, PLY, STL, USD/USDA/USDC, USDZ, SCN, DAE, ABC — same set as the main viewer.

## Notes

- macOS already ships built-in Quick Look for `usdz` and some other formats; this
  extension adds consistent SceneKit-based previews (with orbit/zoom) across the
  full format list.
- If a preview doesn't appear, run `qlmanage -r` to reset the Quick Look cache,
  then re-open Finder.
