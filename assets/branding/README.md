# Application logo

`source/app-logo.png` preserves the final user-selected PVZ seedling grid artwork at its original resolution. `app-logo.png` is its smaller in-app and website variant. Only the smaller variant is bundled with Flutter. Preserve the approved artwork, border treatment and spacing; do not regenerate or redraw it from a prompt.

On macOS, regenerate platform sizes from the repository root:

```sh
swift tool/generate_app_icons.swift
```

Regenerate the compact in-app logo with `python tool/prepare_app_logo.py` (Pillow required).

macOS, Windows and Android preserve transparency. iOS uses an opaque green background because its icon catalog requires opaque artwork and the system applies the outer mask. Icon generation only resizes and packages the approved image.

## Validation

The bundled PNG is a 256 x 256 RGBA downsample of the approved artwork, sized for the 96 logical-pixel in-app logo. It preserves transparency and uses lossless PNG compression after resizing. Platform icon assets retain their existing resolutions and are generated from the original source. Windows is the primary tested platform; see the project platform documentation for the current validation scope.

## macOS Dock refresh

`tool/restart_macos_app.swift` refreshes only the target application’s icon from its bundled `AppIcon.icns` before launch. This avoids stale Dock icons when a build is replaced at the same path and does not clear other applications’ icon caches. Graceful save/quit still completes before the replacement starts.
