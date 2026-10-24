#include "editor_windows.h"
#include "game_bridge.h"
#include "flutter/generated_plugin_registrant.h"
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <functional>
#include <string>
#include <utility>
namespace {
using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
using Channel = flutter::MethodChannel<V>;
using Result = flutter::MethodResult<V>;
using Call = flutter::MethodCall<V>;
const V* Find(const M& m, const char* key) {
  auto it = m.find(V(key)); return it == m.end() ? nullptr : &it->second;
}
std::string Text(const M& m, const char* key, std::string fallback = "") {
  const auto* v = Find(m,key); const auto* s = v ? std::get_if<std::string>(v) : nullptr;
  return s ? *s : fallback;
}
bool Flag(const M& m, const char* key, bool fallback = false) {
  const auto* v=Find(m,key); const auto* b=v ? std::get_if<bool>(v) : nullptr;
  return b ? *b : fallback;
}
M Arguments(const Call& c) {
  const auto* m=c.arguments() ? std::get_if<M>(c.arguments()) : nullptr;
  return m ? *m : M{};
}
void FixedContent(HWND hwnd, int width, int height) {
  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
  SetWindowLongPtr(hwnd,GWL_STYLE,style);
  const UINT dpi=GetDpiForWindow(hwnd);
  RECT rect{0,0,MulDiv(width,static_cast<int>(dpi),96),MulDiv(height,static_cast<int>(dpi),96)};
  AdjustWindowRectExForDpi(&rect, static_cast<DWORD>(style), FALSE,
      static_cast<DWORD>(GetWindowLongPtr(hwnd,GWL_EXSTYLE)),dpi);
  SetWindowPos(hwnd,nullptr,0,0,rect.right-rect.left,rect.bottom-rect.top,
      SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_FRAMECHANGED);
}
void Forward(Channel* channel, const std::string& method, const V* args,
             std::unique_ptr<Result> result,
             std::function<void(const V*)> accepted = {}) {
  if (!channel) { result->Error("window_unavailable", "窗口尚未准备好"); return; }
  auto reply=std::shared_ptr<Result>(std::move(result));
  channel->InvokeMethod(method,args ? std::make_unique<V>(*args) : nullptr,
    std::make_unique<flutter::MethodResultFunctions<V>>(
      [reply,accepted](const V* value) { if (accepted) accepted(value); if(value) reply->Success(*value); else reply->Success(); },
      [reply](const std::string& code,const std::string& message,const V* details) {
        if(details) reply->Error(code,message,*details); else reply->Error(code,message);
      },[reply](){ reply->NotImplemented(); }));
}
class Sidebar : public Win32Window {
 public:
  std::function<bool()> setup;
  std::function<void()> closed;
  std::function<void()> destroyed;
 protected:
  bool OnCreate() override { return setup && setup(); }
  void OnDestroy() override { if(destroyed) destroyed(); Win32Window::OnDestroy(); }
  LRESULT MessageHandler(HWND hwnd,UINT message,WPARAM wparam,LPARAM lparam) noexcept override {
    if(message==WM_CLOSE) { ShowWindow(hwnd,SW_HIDE); if(closed) closed(); return 0; }
    return Win32Window::MessageHandler(hwnd,message,wparam,lparam);
  }
};
}
struct EditorWindows::Impl {
  Win32Window* main;
  flutter::DartProject project;
  std::unique_ptr<Channel> main_channel,toolbox_channel,library_channel;
  std::unique_ptr<Channel> toolbox_game;
  std::unique_ptr<Sidebar> sidebar;
  std::unique_ptr<flutter::FlutterViewController> toolbox;
  V latest;
  M configuration;
  std::string mode="toolbox";
  bool toolbox_ready=false, library_ready=false;
  std::shared_ptr<bool> alive=std::make_shared<bool>(true);
  Impl(Win32Window* owner,flutter::BinaryMessenger* messenger,const flutter::DartProject& p)
      : main(owner),project(p) {
    FixedContent(main->GetHandle(),810,695);
    main_channel=std::make_unique<Channel>(messenger,"pvz_formation_editor/windows",
        &flutter::StandardMethodCodec::GetInstance());
    main_channel->SetMethodCallHandler([this](const Call& call,std::unique_ptr<Result> result){
      Handle(call,std::move(result),false);
    });
  }
  ~Impl() {
    *alive=false;
    if(sidebar) sidebar->Destroy();
    library_channel.reset(); toolbox_channel.reset();
    toolbox_game.reset(); toolbox.reset();
  }
  void Configure(const M& args) {
    for(const char* key : {"dataPath","activeDraftId"}) {
      if(const auto* value=Find(args,key)) configuration[V(key)]=*value;
    }
  }
  void Notify() {
    const bool visible=sidebar && IsWindowVisible(sidebar->GetHandle());
    main_channel->InvokeMethod("sidebarStateChanged",std::make_unique<V>(M{
      {V("visible"),V(visible)},{V("mode"),V(mode)}}));
  }
  void Refresh() {
    if(library_channel) library_channel->InvokeMethod("refresh",std::make_unique<V>(configuration));
  }
  bool EnsureSidebar() {
    if(sidebar) return true;
    sidebar=std::make_unique<Sidebar>();
    sidebar->setup=[this](){ FixedContent(sidebar->GetHandle(),410,695); return EnsureToolbox(); };
    sidebar->closed=[this](){ Notify(); };
    RECT frame{}; GetWindowRect(main->GetHandle(),&frame);
    const UINT dpi=GetDpiForWindow(main->GetHandle());
    const unsigned int x=static_cast<unsigned int>(MulDiv(frame.right+8,96,static_cast<int>(dpi)));
    const unsigned int y=static_cast<unsigned int>(MulDiv(frame.top,96,static_cast<int>(dpi)));
    if(!sidebar->Create(L"布阵器工具箱",Win32Window::Point(x,y),Win32Window::Size(410,695))) {
      sidebar.reset(); return false;
    }
    // Independent top-level window: minimizing the editor must not hide the sidebar.
    // Impl still destroys the sidebar when the main window closes.
    SetWindowPos(sidebar->GetHandle(),nullptr,frame.right+8,frame.top,0,0,
        SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
    return true;
  }
  bool EnsureToolbox() {
    if(toolbox) return true;
    auto p=project; p.set_dart_entrypoint("toolboxMain");
    toolbox=std::make_unique<flutter::FlutterViewController>(410,695,p);
    if(!toolbox->engine() || !toolbox->view()) return false;
    RegisterPlugins(toolbox->engine());
    auto messenger=toolbox->engine()->messenger();
    toolbox_game=RegisterGameBridge(messenger);
    toolbox_channel=std::make_unique<Channel>(messenger,"pvz_formation_editor/windows",&flutter::StandardMethodCodec::GetInstance());
    toolbox_channel->SetMethodCallHandler([this](const Call& c,std::unique_ptr<Result> r){ Handle(c,std::move(r),true); });
    sidebar->SetChildContent(toolbox->view()->GetNativeWindow());
    return true;
  }
  bool EnsureLibrary() {
    if(library_channel) return true;
    if(Text(configuration,"dataPath").empty() || !toolbox) return false;
    auto messenger=toolbox->engine()->messenger();
    library_channel=std::make_unique<Channel>(messenger,"pvz_formation_editor/library",&flutter::StandardMethodCodec::GetInstance());
    library_channel->SetMethodCallHandler([this](const Call& call,std::unique_ptr<Result> result){
      const auto& method=call.method_name();
      if(method=="ready") { library_ready=true; result->Success(V(configuration)); return; }
      if(method=="prepareDedup") {
        Forward(main_channel.get(),"libraryPrepareDedup",call.arguments(),std::move(result)); return;
      }
      if(method=="openEditor") {
        auto guard=alive;
        Forward(main_channel.get(),"libraryOpen",call.arguments(),std::move(result),[this,guard](const V* value){
          const auto* ok=value ? std::get_if<bool>(value) : nullptr;
          if(*guard && ok && *ok) Select("toolbox",true);
        }); return;
      }
      if(method=="showToolbox" || method=="activateWindow") { result->Success(V(Select("toolbox",true))); return; }
      Handle(call,std::move(result),true);
    });
    return true;
  }
  bool Select(const std::string& selected,bool show) {
    if(selected!="toolbox" && selected!="library") return false;
    if(!EnsureSidebar() || (selected=="library" && !EnsureLibrary())) return false;
    mode=selected;
    sidebar->SetChildContent(toolbox->view()->GetNativeWindow());
    toolbox_channel->InvokeMethod("selectSidebarPage",std::make_unique<V>(selected));
    SetWindowTextW(sidebar->GetHandle(),L"布阵器工具箱");
    if(show) {
      if(IsIconic(sidebar->GetHandle())) ShowWindow(sidebar->GetHandle(),SW_RESTORE);
      sidebar->Show(); SetForegroundWindow(sidebar->GetHandle());
    }
    if(selected=="library") Refresh();
    Notify(); return true;
  }
  void Handle(const Call& call,std::unique_ptr<Result> result,bool secondary) {
    const auto& method=call.method_name(); const auto args=Arguments(call);
    Configure(args);
    if(method=="getDialogOwner") {
      HWND owner=secondary && sidebar ? sidebar->GetHandle() : main->GetHandle();
      result->Success(V(static_cast<int64_t>(reinterpret_cast<intptr_t>(owner)))); return;
    }
    if(method=="initialize") { result->Success(V(Select("toolbox",false))); return; }
    if(method=="ready") { toolbox_ready=true; result->Success(latest); return; }
    if(method=="publishState") {
      if(!std::holds_alternative<M>(call.arguments() ? *call.arguments() : V())) {
        result->Error("arguments","窗口状态必须是对象"); return;
      }
      latest=*call.arguments();
      if(const auto* id=Find(args,"activeDraftId")) configuration[V("activeDraftId")]=*id;
      if(toolbox_channel) toolbox_channel->InvokeMethod("receiveState",std::make_unique<V>(latest));
      result->Success(V(true)); return;
    }
    if(method=="editState" && secondary) { Forward(main_channel.get(),"applyToolboxState",call.arguments(),std::move(result)); return; }
    if(method=="mainAction" && secondary) { Forward(main_channel.get(),"mainAction",call.arguments(),std::move(result)); return; }
    if(method=="showLibrary") { result->Success(V(Select("library",true))); return; }
    if(method=="selectSidebarMode") {
      const bool selected=Select(Text(args,"mode"),true);
      if(selected && Text(args,"mode")=="toolbox") {
        if(const auto* tab=Find(args,"toolboxTab"); tab && toolbox_channel)
          toolbox_channel->InvokeMethod("selectToolboxTab",std::make_unique<V>(*tab));
      }
      result->Success(V(selected)); return;
    }
    if(method=="configureSidebar") { result->Success(V(true)); return; }
    if(method=="refreshLibrary") { Refresh(); result->Success(); return; }
    if(method=="setSidebarVisible" || method=="setToolboxVisible") {
      bool ok=true;
      if(Flag(args,"visible")) ok=Select(mode,true);
      else if(sidebar) {
        if(Flag(args,"restoreIfMinimized") && IsIconic(sidebar->GetHandle())) ok=Select(mode,true);
        else { ShowWindow(sidebar->GetHandle(),SW_HIDE); Notify(); }
      }
      result->Success(V(ok)); return;
    }
    if(method=="deactivate") {
      latest=V(); if(sidebar) ShowWindow(sidebar->GetHandle(),SW_HIDE);
      Notify(); result->Success(V(true)); return;
    }
    if(method=="activateWindow") {
      if(secondary) result->Success(V(Select(mode,true)));
      else { main->Show(); SetForegroundWindow(main->GetHandle()); result->Success(V(true)); }
      return;
    }
#ifndef NDEBUG
    if(method=="requestCloseForTest") {
      result->Success();
      PostMessage(main->GetHandle(),WM_CLOSE,0,0);
      return;
    }
#endif
    if(method=="resourceDiagnostics") {
      if(toolbox_channel) Forward(toolbox_channel.get(),method,nullptr,std::move(result));
      else result->Success();
      return;
    }
    if(method=="diagnostics") {
      auto dimensions=[](HWND hwnd) {
        RECT r{}; if(hwnd) GetClientRect(hwnd,&r);
        const double dpi=hwnd ? static_cast<double>(GetDpiForWindow(hwnd))/96.0 : 1.0;
        return flutter::EncodableList{V((r.right-r.left)/dpi),V((r.bottom-r.top)/dpi)};
      };
      auto frame=[](HWND hwnd) {
        RECT r{}; if(hwnd) GetWindowRect(hwnd,&r);
        return flutter::EncodableList{V(static_cast<int32_t>(r.left)),V(static_cast<int32_t>(r.top)),
          V(static_cast<int32_t>(r.right-r.left)),V(static_cast<int32_t>(r.bottom-r.top))};
      };
      result->Success(V(M{{V("sharedSidebarWindow"),V(true)},
        {V("sidebarVisible"),V(sidebar && IsWindowVisible(sidebar->GetHandle())!=FALSE)},
        {V("sidebarMinimized"),V(sidebar && IsIconic(sidebar->GetHandle())!=FALSE)},
        {V("sidebarMode"),V(mode)},{V("hasToolboxEngine"),V(toolbox!=nullptr)},
        {V("hasLibraryEngine"),V(false)},{V("sidebarEngineCount"),V(toolbox ? 1 : 0)},
        {V("toolboxReady"),V(toolbox_ready)},{V("libraryReady"),V(library_ready)},
        {V("mainContentSize"),V(dimensions(main->GetHandle()))},
        {V("sidebarContentSize"),V(dimensions(sidebar ? sidebar->GetHandle() : nullptr))},
        {V("mainFrame"),V(frame(main->GetHandle()))},
        {V("sidebarFrame"),V(frame(sidebar ? sidebar->GetHandle() : nullptr))},
        {V("sidebarWindowNumber"),V(static_cast<int64_t>(reinterpret_cast<intptr_t>(sidebar ? sidebar->GetHandle() : nullptr)))}})); return;
    }
    result->NotImplemented();
  }
};
EditorWindows::EditorWindows(Win32Window* main,flutter::BinaryMessenger* messenger,const flutter::DartProject& project)
    : impl_(std::make_unique<Impl>(main,messenger,project)) {}
EditorWindows::~EditorWindows() = default;
