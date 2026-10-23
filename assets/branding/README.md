# Application logo

`app-logo.png` is the final user-selected PVZ seedling grid artwork, supplied as `13269167-73fd-4586-8801-f0aeb34c172f.png`. This source replaces the earlier imagegen previews. Preserve its artwork, border treatment and spacing when packaging; do not regenerate or redraw it from a prompt.

On macOS, regenerate platform sizes from the repository root:

```sh
swift tool/generate_app_icons.swift
```

macOS, Windows and Android preserve transparency. iOS uses an opaque green background because its icon catalog requires opaque artwork and the system applies the outer mask. Icon generation only resizes and packages the approved image.

## Validation

The master PNG matches the final user-supplied file byte for byte. All catalog dimensions and the seven Windows ICO images were checked; iOS icons have no alpha channel. The macOS Debug application built successfully. iOS, Android and Windows builds were not run.
