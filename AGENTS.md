# Application launch

- When starting an updated macOS build, replace existing instances rather than
  adding another copy. Use `swift tool/restart_macos_app.swift <app-bundle-path>`.
- Allow the old application to save and quit normally before launching the new
  build. Do not use `open -n`, force-quit, or leave older instances hidden.
- If graceful quit fails, preserve the running application and report the error;
  do not launch another instance over it.
