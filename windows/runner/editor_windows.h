#ifndef RUNNER_EDITOR_WINDOWS_H_
#define RUNNER_EDITOR_WINDOWS_H_
#include <flutter/binary_messenger.h>
#include <flutter/dart_project.h>
#include <memory>
#include "win32_window.h"
class EditorWindows {
 public:
  EditorWindows(Win32Window* main, flutter::BinaryMessenger* messenger,
                const flutter::DartProject& project);
  ~EditorWindows();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
