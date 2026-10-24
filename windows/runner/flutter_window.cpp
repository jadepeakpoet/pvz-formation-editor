#include "flutter_window.h"
#include "game_bridge.h"

#include <optional>
#include <fstream>
namespace {
void TraceClose(const char* stage) {
  char path[32768];
  const auto size = GetEnvironmentVariableA("PVZ_CLOSE_TRACE", path, sizeof(path));
  if (size > 0 && size < sizeof(path)) { std::ofstream log(path, std::ios::app); log << stage << std::endl; }
}
}

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Create() first calls Destroy(), even for a fresh window. Start a new
  // callback lifetime here; otherwise every prepareExit reply is ignored.
  lifecycle_alive_ = std::make_shared<bool>(true);
  close_pending_ = false;
  close_approved_ = false;
  TraceClose("create-lifetime-start");
  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  game_channel_ = RegisterGameBridge(flutter_controller_->engine()->messenger());
  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "pvz_formation_editor/lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  editor_windows_ = std::make_unique<EditorWindows>(this, flutter_controller_->engine()->messenger(), project_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  TraceClose("destroy-start");
  *lifecycle_alive_ = false;
  TraceClose("sidebar-destroy-start");
  editor_windows_.reset();
  TraceClose("sidebar-destroy-done");
  lifecycle_channel_.reset();
  game_channel_.reset();
  if (flutter_controller_) {
    TraceClose("main-engine-destroy-start");
    flutter_controller_ = nullptr;
    TraceClose("main-engine-destroy-done");
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Keep the engine and its SQLite connection alive until Dart confirms its flush.
  if (message == WM_CLOSE && !close_approved_ && lifecycle_channel_) {
    if (close_pending_) return 0;
    TraceClose("prepare-exit-request");
    close_pending_ = true;
    auto alive = lifecycle_alive_;
    lifecycle_channel_->InvokeMethod(
        "prepareExit", nullptr,
        std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
            [this, alive, hwnd](const flutter::EncodableValue* value) {
              if (!*alive) return;
              const bool* approved = value ? std::get_if<bool>(value) : nullptr;
              TraceClose(approved && *approved ? "prepare-exit-approved" : "prepare-exit-veto");
              if (approved && *approved) {
                close_approved_ = true;
                // Defer destruction until after the platform-channel reply unwinds.
                PostMessage(hwnd, WM_CLOSE, 0, 0);
              } else {
                close_pending_ = false;
              }
            },
            [this, alive](const std::string&, const std::string&,
                          const flutter::EncodableValue*) {
              if (*alive) close_pending_ = false;
            },
            [this, alive]() {
              if (*alive) close_pending_ = false;
            }));
    return 0;
  }

  if (message == WM_CLOSE && close_approved_) {
    TraceClose("approved-native-close");
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
