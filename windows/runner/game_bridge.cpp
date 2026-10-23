#include "game_bridge.h"
#include "game_pe.h"
#include "game_x86.h"
#include <algorithm>
#include <atomic>
#include <climits>
#include <cstring>
#include <flutter/standard_method_codec.h>
#include <fstream>
#include <shlobj.h>
#include <stdexcept>
#include <string>
#include <thread>
#include <tlhelp32.h>
#include <tuple>
#include <vector>
#include <windows.h>
namespace {
using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
using L = flutter::EncodableList;
struct Handle {
  HANDLE h;
  ~Handle() {
    if (h && h != INVALID_HANDLE_VALUE)
      CloseHandle(h);
  }
};
std::string Utf8(const std::wstring &s) {
  if (s.empty())
    return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0, nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}
template <class T> T Read(HANDLE p, uintptr_t a) {
  T value{};
  SIZE_T n = 0;
  if (!ReadProcessMemory(p, reinterpret_cast<LPCVOID>(a), &value, sizeof(value),
                         &n) ||
      n != sizeof(value))
    throw std::runtime_error("游戏内存读取失败，请检查权限或重新连接");
  return value;
}
bool WriteCompatible(HANDLE process, const std::string &executable);
struct Target {
  DWORD pid;
  uint32_t stamp;
  uintptr_t base;
  std::string title, path;
  bool supported;
};
Target Inspect(HWND w) {
  Target t{};
  GetWindowThreadProcessId(w, &t.pid);
  wchar_t title[512]{};
  GetWindowTextW(w, title, 512);
  t.title = Utf8(title);
  Handle p{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
                       FALSE, t.pid)};
  if (!p.h)
    throw std::runtime_error("无权读取游戏进程");
  wchar_t path[32768];
  DWORD size = 32768;
  if (QueryFullProcessImageNameW(p.h, 0, path, &size))
    t.path = Utf8(std::wstring(path, size));
  Handle modules{
      CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, t.pid)};
  MODULEENTRY32 entry{};
  entry.dwSize = sizeof(entry);
  if (!Module32First(modules.h, &entry))
    throw std::runtime_error("无法识别游戏模块");
  t.base = reinterpret_cast<uintptr_t>(entry.modBaseAddr);
  const auto dos = Read<IMAGE_DOS_HEADER>(p.h, t.base);
  if (dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < 64 ||
      dos.e_lfanew > 1048576)
    throw std::runtime_error("游戏程序格式无法识别");
  const auto nt = Read<IMAGE_NT_HEADERS32>(p.h, t.base + dos.e_lfanew);
  if (nt.Signature != IMAGE_NT_SIGNATURE ||
      nt.FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
      nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC)
    throw std::runtime_error("仅支持已识别的32位原版游戏");
  t.stamp = nt.FileHeader.TimeDateStamp;
  t.supported = t.base == 0x400000 && t.stamp == 0x49ecf563;
  return t;
}
BOOL CALLBACK Discover(HWND w, LPARAM output) {
  wchar_t cls[80]{};
  GetClassNameW(w, cls, 80);
  if (wcscmp(cls, L"MainWindow") != 0)
    return TRUE;
  try {
    const auto t = Inspect(w);
    reinterpret_cast<L *>(output)->push_back(
        V(M{{V("pid"), V(static_cast<int64_t>(t.pid))},
            {V("title"), V(t.title)},
            {V("executable"), V(t.path)},
            {V("version"), V(t.supported ? "1.0.0.1051 en" : "未适配版本")},
            {V("timestamp"), V(static_cast<int64_t>(t.stamp))},
            {V("canRead"), V(t.supported)},
            {V("canWrite"), V(t.supported && [&]() {
               Handle process{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION |
                                              PROCESS_VM_READ,
                                          FALSE, t.pid)};
               return process.h && WriteCompatible(process.h, t.path);
             }())}}));
  } catch (const std::exception &) { /* Unreadable windows must never be treated
                                        as supported games. */
  }
  return TRUE;
}
HWND FindPid(DWORD pid) {
  HWND found = nullptr;
  struct Search {
    DWORD pid;
    HWND *found;
  } data{pid, &found};
  EnumWindows(
      [](HWND w, LPARAM l) -> BOOL {
        auto *d = reinterpret_cast<Search *>(l);
        DWORD p = 0;
        GetWindowThreadProcessId(w, &p);
        wchar_t cls[80]{};
        GetClassNameW(w, cls, 80);
        if (p == d->pid && wcscmp(cls, L"MainWindow") == 0) {
          *d->found = w;
          return FALSE;
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&data));
  return found;
}
M ReadBoard(DWORD pid) {
  HWND w = FindPid(pid);
  if (!w)
    throw std::runtime_error("游戏已退出");
  const auto t = Inspect(w);
  if (!t.supported)
    throw std::runtime_error("当前游戏版本尚未适配，未读取阵型");
  Handle p{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
                       FALSE, pid)};
  if (!p.h)
    throw std::runtime_error("无权读取游戏");
  const uint32_t lawn = Read<uint32_t>(p.h, 0x6a9ec0);
  if (!lawn)
    throw std::runtime_error("游戏尚未就绪");
  const auto ui = Read<int32_t>(p.h, lawn + 0x7fc);
  if (ui != 2 && ui != 3)
    throw std::runtime_error("请先进入选卡或布阵场景");
  const uint32_t board = Read<uint32_t>(p.h, lawn + 0x768);
  if (!board)
    throw std::runtime_error("当前没有可读取的场地");
  const auto scene = Read<int32_t>(p.h, board + 0x554c);
  if (scene < 0 || scene > 5)
    throw std::runtime_error("当前场景不受支持");
  const char *maps[] = {"day", "night", "pool", "fog", "roof", "moonRoof"};
  L pieces;
  const auto plants = Read<uint32_t>(p.h, board + 0xac),
             count = Read<uint32_t>(p.h, board + 0xb0);
  if (count > 4096 || (count && !plants))
    throw std::runtime_error("植物数组校验失败");
  for (uint32_t i = 0; i < count; i++) {
    uintptr_t a = plants + i * 0x14c;
    if (Read<uint8_t>(p.h, a + 0x141) || Read<uint8_t>(p.h, a + 0x142))
      continue;
    const auto type = Read<int32_t>(p.h, a + 0x24),
               row = Read<int32_t>(p.h, a + 0x1c),
               col = Read<int32_t>(p.h, a + 0x28);
    if (type < 0 || type > 47 || row < 0 || row > 5 || col < 0 || col > 8)
      throw std::runtime_error("植物记录超出原版范围");
    pieces.push_back(
        V(M{{V("type"), V(type)},
            {V("row"), V(row)},
            {V("col"), V(col)},
            {V("imitater"), V(Read<int32_t>(p.h, a + 0x138) == 48)},
            {V("asleep"), V(Read<uint8_t>(p.h, a + 0x143) != 0)}}));
  }
  const auto grids = Read<uint32_t>(p.h, board + 0x11c),
             gridCount = Read<uint32_t>(p.h, board + 0x120);
  if (gridCount > 4096 || (gridCount && !grids))
    throw std::runtime_error("道具数组校验失败");
  for (uint32_t i = 0; i < gridCount; i++) {
    uintptr_t a = grids + i * 0xec;
    if (Read<uint8_t>(p.h, a + 0x20))
      continue;
    int type = Read<int32_t>(p.h, a + 8);
    if (type != 1 && type != 3 && type != 11)
      continue;
    int row = Read<int32_t>(p.h, a + 0x14), col = Read<int32_t>(p.h, a + 0x10);
    if (row < 0 || row > 5 || col < 0 || col > 8)
      throw std::runtime_error("道具记录超出原版范围");
    pieces.push_back(
        V(M{{V("gridType"), V(type)}, {V("row"), V(row)}, {V("col"), V(col)}}));
  }
  if (Read<uint32_t>(p.h, lawn + 0x768) != board)
    throw std::runtime_error("读取期间场景发生变化，请重试");
  return M{{V("pid"), V(static_cast<int64_t>(pid))},
           {V("version"), V("1.0.0.1051 en")},
           {V("map"), V(maps[scene])},
           {V("sunValue"), V(Read<int32_t>(p.h, board + 0x5560))},
           {V("pieces"), V(pieces)}};
}
std::wstring Wide(const std::string &value) {
  const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                    static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(n, L'\0');
  if (n)
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), n);
  return result;
}
bool EntryMatchesDisk(HANDLE process, HANDLE file, uint32_t address) {
  auto readAt = [file](uint64_t offset, void *output, size_t length) {
    LARGE_INTEGER at{};
    at.QuadPart = static_cast<LONGLONG>(offset);
    DWORD read = 0;
    return SetFilePointerEx(file, at, nullptr, FILE_BEGIN) &&
           ReadFile(file, output, static_cast<DWORD>(length), &read, nullptr) &&
           read == length;
  };
  uint64_t offset = 0;
  if (!GamePe1051EntryOffset(readAt, address, 32, offset))
    return false;
  unsigned char disk[32]{}, memory[32]{};
  SIZE_T bytes = 0;
  if (!readAt(offset, disk, 32) ||
      !ReadProcessMemory(
          process, reinterpret_cast<LPCVOID>(static_cast<uintptr_t>(address)),
          memory, 32, &bytes) ||
      bytes != 32)
    return false;
  return memcmp(disk, memory, 32) == 0 && disk[0] != 0 && disk[0] != 0xcc &&
         disk[0] != 0xe9;
}

bool WriteCompatible(HANDLE process, const std::string &executable) {
  try {
    if (Read<uint8_t>(process, 0x552014) != 0xdb)
      return false;
    Handle file{
        CreateFileW(Wide(executable).c_str(), GENERIC_READ,
                    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr)};
    if (file.h == INVALID_HANDLE_VALUE)
      return false;
    // This is a live/disk code consistency check, not a claim of an official
    // hash.
    return EntryMatchesDisk(process, file.h, 0x40d120) &&
           EntryMatchesDisk(process, file.h, 0x4679b0);
  } catch (...) {
    return false;
  }
}
int Number(const M &value, const char *key) {
  auto it = value.find(V(key));
  if (it == value.end())
    throw std::runtime_error("缺少阵型字段");
  if (auto n = std::get_if<int32_t>(&it->second))
    return *n;
  if (auto n = std::get_if<int64_t>(&it->second)) {
    if (*n >= INT_MIN && *n <= INT_MAX)
      return static_cast<int>(*n);
  }
  throw std::runtime_error("阵型数字字段无效");
}
const M &Object(const V &v) {
  const auto *map = std::get_if<M>(&v);
  if (!map)
    throw std::runtime_error("阵型结构无效");
  return *map;
}
const V &Field(const M &value, const char *key) {
  auto it = value.find(V(key));
  if (it == value.end())
    throw std::runtime_error("缺少阵型字段");
  return it->second;
}
bool Flag(const M &value, const char *key) {
  auto it = value.find(V(key));
  return it != value.end() && std::get_if<bool>(&it->second) &&
         std::get<bool>(it->second);
}
void RequireRepresentable(const M &snapshot) {
  const auto &map = std::get<std::string>(Field(snapshot, "map"));
  const bool daytime = map == "day" || map == "pool" || map == "roof";
  const auto &pieces = std::get<L>(Field(snapshot, "pieces"));
  if (pieces.size() > 512)
    throw std::runtime_error("当前一次最多应用512个植物");
  for (const auto &item : pieces) {
    const auto &p = Object(item);
    if (p.find(V("gridType")) != p.end())
      throw std::runtime_error("当前版本尚不支持覆盖含墓碑、梯子或钉耙的阵型");
    const int type = Number(p, "type"), row = Number(p, "row"),
              col = Number(p, "col");
    if (type < 0 || type > 47 || row < 0 ||
        row > (map == "pool" || map == "fog" ? 5 : 4) || col < 0 || col > 8)
      throw std::runtime_error("阵型植物或坐标超出原版场地");
    if (Flag(p, "imitater"))
      throw std::runtime_error("当前版本尚不支持覆盖含模仿者的阵型");
    const bool mushroom = type == 8 || type == 9 || type == 10 || type == 12 ||
                          type == 13 || type == 14 || type == 15 ||
                          type == 24 || type == 31 || type == 42;
    if (Flag(p, "asleep") || (daytime && mushroom))
      throw std::runtime_error("白天蘑菇与睡眠状态尚未适配，未修改游戏");
  }
}

std::vector<std::tuple<int, int, int, bool, bool>>
Composition(const M &snapshot) {
  std::vector<std::tuple<int, int, int, bool, bool>> value;
  for (const auto &p : std::get<L>(Field(snapshot, "pieces"))) {
    const auto &m = Object(p);
    value.emplace_back(Number(m, "type"), Number(m, "row"), Number(m, "col"),
                       Flag(m, "imitater"), Flag(m, "asleep"));
  }
  std::sort(value.begin(), value.end());
  return value;
}
std::atomic<bool> pendingWrite{false};
std::atomic<DWORD> blockedPid{0};
void WriteBytes(HANDLE process, uintptr_t address, const void *data,
                SIZE_T size) {
  SIZE_T bytes = 0;
  if (!WriteProcessMemory(process, reinterpret_cast<LPVOID>(address), data,
                          size, &bytes) ||
      bytes != size)
    throw std::runtime_error("写入游戏内存失败");
}
// All restoration paths verify the byte; failure remains visible and blocks
// writes.
bool RestoreLoopByte(HANDLE process, DWORD desiredProtection = 0) noexcept {
  for (int attempt = 0; attempt < 3; attempt++) {
    if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0)
      return true;
    DWORD old = 0;
    if (VirtualProtectEx(process, reinterpret_cast<LPVOID>(0x552014), 1,
                         PAGE_EXECUTE_READWRITE, &old)) {
      const uint8_t original = 0xdb;
      SIZE_T size = 0;
      const BOOL written = WriteProcessMemory(
          process, reinterpret_cast<LPVOID>(0x552014), &original, 1, &size);
      FlushInstructionCache(process, reinterpret_cast<LPVOID>(0x552014), 1);
      DWORD ignored = 0;
      const BOOL protectedAgain = VirtualProtectEx(
          process, reinterpret_cast<LPVOID>(0x552014), 1,
          desiredProtection ? desiredProtection : old, &ignored);
      uint8_t actual = 0;
      SIZE_T read = 0;
      if (written && size == 1 && protectedAgain &&
          ReadProcessMemory(process, reinterpret_cast<LPCVOID>(0x552014),
                            &actual, 1, &read) &&
          read == 1 && actual == 0xdb)
        return true;
    }
    Sleep(30);
  }
  return WaitForSingleObject(process, 0) == WAIT_OBJECT_0;
}
struct LoopGuard {
  HANDLE process;
  DWORD pid;
  DWORD originalProtection = 0;
  bool changed = false;
  explicit LoopGuard(HANDLE p, DWORD targetPid) : process(p), pid(targetPid) {
    const uint8_t block = 0xfe;
    DWORD old = 0;
    if (!VirtualProtectEx(p, reinterpret_cast<LPVOID>(0x552014), 1,
                          PAGE_EXECUTE_READWRITE, &old))
      throw std::runtime_error("无法暂时停止游戏主循环");
    originalProtection = old;
    try {
      WriteBytes(p, 0x552014, &block, 1);
      changed = true;
      FlushInstructionCache(p, reinterpret_cast<LPVOID>(0x552014), 1);
    } catch (...) {
      DWORD ignored;
      VirtualProtectEx(p, reinterpret_cast<LPVOID>(0x552014), 1, old, &ignored);
      if (!RestoreLoopByte(p, originalProtection))
        blockedPid = pid;
      throw;
    }
    DWORD ignored;
    if (!VirtualProtectEx(p, reinterpret_cast<LPVOID>(0x552014), 1, old,
                          &ignored)) {
      if (!Restore())
        blockedPid = pid;
      throw std::runtime_error("游戏代码页保护恢复失败，未应用阵型");
    }
  }
  bool Restore() noexcept {
    if (!changed)
      return true;
    if (!RestoreLoopByte(process, originalProtection)) {
      blockedPid = pid;
      return false;
    }
    changed = false;
    DWORD expected = pid;
    blockedPid.compare_exchange_strong(expected, 0);
    return true;
  }
  ~LoopGuard() { Restore(); }
};
using X86 = GameX86;

M ApplyBoard(DWORD pid, const M &target, const M &expected) {
  const DWORD blocked = blockedPid.load();
  if (blocked) {
    Handle oldProcess{OpenProcess(SYNCHRONIZE, FALSE, blocked)};
    if ((!oldProcess.h && GetLastError() == ERROR_INVALID_PARAMETER) ||
        (oldProcess.h &&
         WaitForSingleObject(oldProcess.h, 0) == WAIT_OBJECT_0)) {
      blockedPid = 0;
      pendingWrite = false;
    } else
      throw std::runtime_error(
          "上次游戏主循环恢复未能确认，请先重新启动游戏；备份已保留");
  }
  if (pendingWrite.exchange(true))
    throw std::runtime_error("上一次游戏操作尚未结束，请稍后重试");
  struct Pending {
    bool transfer = false;
    ~Pending() {
      if (!transfer && blockedPid.load() == 0)
        pendingWrite = false;
    }
  } pending;
  const auto t = Inspect(FindPid(pid));
  Handle process{OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ |
                                 PROCESS_VM_WRITE | PROCESS_VM_OPERATION |
                                 PROCESS_CREATE_THREAD | SYNCHRONIZE,
                             FALSE, pid)};
  if (!t.supported || !process.h || !WriteCompatible(process.h, t.path))
    throw std::runtime_error("当前原版1051程序的内存与磁盘代码校验未通过");
  RequireRepresentable(target);
  RequireRepresentable(expected);
  if (Field(target, "map") != Field(expected, "map"))
    throw std::runtime_error("目前仅支持应用到相同场地，未修改游戏");
  const uint32_t lawn = Read<uint32_t>(process.h, 0x6a9ec0),
                 board = Read<uint32_t>(process.h, lawn + 0x768);
  const int mode = Read<int32_t>(process.h, lawn + 0x7f8);
  if (!((mode >= 11 && mode <= 15) || (mode >= 61 && mode <= 70)))
    throw std::runtime_error("请进入生存无尽或我是僵尸布阵模式后应用");
  if (mode >= 61)
    throw std::runtime_error("我是僵尸外观构造尚未适配，未修改游戏");
  LoopGuard loop(process.h, pid);
  const auto duration = Read<int32_t>(process.h, lawn + 0x454);
  if (duration < 1 || duration > 100)
    throw std::runtime_error("游戏帧时长校验失败");
  Sleep(static_cast<DWORD>(duration * 2 + 20));
  if (Read<uint32_t>(process.h, lawn + 0x768) != board)
    throw std::runtime_error("游戏场地在操作前发生变化，未应用阵型");
  const M before = ReadBoard(pid);
  if (Field(before, "map") != Field(expected, "map") ||
      Composition(before) != Composition(expected) ||
      Field(before, "sunValue") != Field(expected, "sunValue"))
    throw std::runtime_error(
        "游戏阵型在备份后发生变化，请重新读取并备份后重试");
  const int sun = Number(target, "sunValue");
  if (sun < 0 || sun > 999999)
    throw std::runtime_error("目标阳光值无效");
  X86 code;
  code.Byte(0x60); // Preserve registers for the remote thread entry.
  const auto plants = Read<uint32_t>(process.h, board + 0xac),
             count = Read<uint32_t>(process.h, board + 0xb0);
  for (uint32_t i = 0; i < count; i++) {
    uint32_t address = plants + i * 0x14c;
    if (!Read<uint8_t>(process.h, address + 0x141) &&
        !Read<uint8_t>(process.h, address + 0x142)) {
      code.Push(address);
      code.Call(0x4679b0);
    }
  }
  auto pieces = std::get<L>(Field(target, "pieces"));
  auto order = [](int type) {
    return type == 16 || type == 33 ? 0 : type == 30 ? 2 : type == 35 ? 3 : 1;
  };
  std::stable_sort(pieces.begin(), pieces.end(), [&](const V &a, const V &b) {
    return order(Number(Object(a), "type")) < order(Number(Object(b), "type"));
  });
  for (const auto &item : pieces) {
    const auto &p = Object(item);
    code.Push(0xffffffff);
    code.Push(static_cast<uint32_t>(Number(p, "type")));
    code.MovEax(static_cast<uint32_t>(Number(p, "row")));
    code.Push(static_cast<uint32_t>(Number(p, "col")));
    code.Push(board);
    code.Call(0x40d120);
  }
  code.Byte(0x61);
  code.Byte(0x31);
  code.Byte(0xc0);
  code.Byte(0xc2);
  code.Byte(0x04);
  code.Byte(0x00);
  LPVOID allocation = VirtualAllocEx(process.h, nullptr, code.bytes.size(),
                                     MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
  if (!allocation)
    throw std::runtime_error("无法分配游戏调用缓冲区");
  HANDLE thread = nullptr;
  try {
    const auto base = reinterpret_cast<uintptr_t>(allocation);
    if (base > MAXDWORD)
      throw std::runtime_error("游戏调用地址超出32位范围");
    code.Relocate(static_cast<uint32_t>(base));
    WriteBytes(process.h, base, code.bytes.data(), code.bytes.size());
    DWORD old = 0;
    if (!VirtualProtectEx(process.h, allocation, code.bytes.size(),
                          PAGE_EXECUTE_READ, &old))
      throw std::runtime_error("无法保护游戏调用缓冲区");
    FlushInstructionCache(process.h, allocation, code.bytes.size());
    thread =
        CreateRemoteThread(process.h, nullptr, 0,
                           reinterpret_cast<LPTHREAD_START_ROUTINE>(allocation),
                           nullptr, 0, nullptr);
    if (!thread)
      throw std::runtime_error("无法调用游戏植物构造函数");
    if (WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0) {
      // Never free executable memory or unblock the game while its thread runs.
      HANDLE retained = process.h;
      process.h = nullptr;
      loop.changed = false;
      pending.transfer = true;
      const DWORD originalProtection = loop.originalProtection;
      std::thread([retained, thread, allocation, pid, originalProtection]() {
        if (WaitForSingleObject(thread, INFINITE) != WAIT_OBJECT_0) {
          // Thread completion is unproven: retain executable allocation in the
          // game, keep writes blocked, and require game restart.
          blockedPid = pid;
          CloseHandle(retained);
          CloseHandle(thread);
          return;
        }
        const bool restored = RestoreLoopByte(retained, originalProtection);
        if (!restored)
          blockedPid = pid;
        VirtualFreeEx(retained, allocation, 0, MEM_RELEASE);
        CloseHandle(retained);
        CloseHandle(thread);
        if (restored)
          pendingWrite = false;
      }).detach();
      allocation = nullptr;
      thread = nullptr;
      throw std::runtime_error("游戏调用超时，可能已部分应用；已保留备份，后台"
                               "等待调用结束后恢复主循环");
    }
    DWORD exit = 0;
    if (!GetExitCodeThread(thread, &exit) || exit != 0)
      throw std::runtime_error(
          "游戏构造函数异常退出，可能已部分应用；请使用备份恢复");
    WriteBytes(process.h, board + 0x5560, &sun, sizeof(sun));
    CloseHandle(thread);
    thread = nullptr;
    VirtualFreeEx(process.h, allocation, 0, MEM_RELEASE);
    allocation = nullptr;
    const M after = ReadBoard(pid);
    if (Composition(after) != Composition(target) ||
        Field(after, "sunValue") != Field(target, "sunValue"))
      throw std::runtime_error(
          "应用后阵型校验不一致，可能已部分应用；请使用备份恢复");
    if (!loop.Restore())
      throw std::runtime_error(
          "阵型已应用但主循环恢复校验失败，请保留备份并重新启动游戏");
    return M{{V("before"), V(before)}, {V("after"), V(after)}};
  } catch (...) {
    if (thread)
      CloseHandle(thread);
    if (allocation)
      VirtualFreeEx(process.h, allocation, 0, MEM_RELEASE);
    throw;
  }
}
L SaveFolders(DWORD pid) {
  const auto t = Inspect(FindPid(pid));
  L out;
  std::vector<std::wstring> paths;
  const auto exe = Wide(t.path);
  const auto slash = exe.find_last_of(L"\\/");
  if (slash != std::wstring::npos)
    paths.push_back(exe.substr(0, slash) + L"\\userdata");
  wchar_t common[MAX_PATH]{};
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_COMMON_APPDATA, nullptr, 0,
                                 common))) {
    for (const auto *suffix : {L"\\PopCap Games\\PlantsVsZombies\\userdata",
                               L"\\PopCap Games\\BloomAndDoom\\userdata"})
      paths.push_back(std::wstring(common) + suffix);
  }
  for (const auto &path : paths) {
    const auto attr = GetFileAttributesW(path.c_str());
    if (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY))
      out.push_back(V(Utf8(path)));
  }
  return out;
}

void CollectSaveFiles(const std::wstring &directory,
                      const std::wstring &relative, L &out, int depth) {
  if (depth > 8)
    throw std::runtime_error("游戏存档目录层级超出限制");
  const auto folder = directory + (relative.empty() ? L"" : L"\\" + relative);
  WIN32_FIND_DATAW entry{};
  HANDLE search = FindFirstFileW((folder + L"\\*").c_str(), &entry);
  if (search == INVALID_HANDLE_VALUE) {
    if (GetLastError() == ERROR_FILE_NOT_FOUND)
      return;
    throw std::runtime_error("无法读取游戏存档目录");
  }
  try {
    do {
      const std::wstring name(entry.cFileName);
      if (name == L"." || name == L"..")
        continue;
      if (entry.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
        continue;
      const auto rel = relative.empty() ? name : relative + L"\\" + name;
      if (entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        CollectSaveFiles(directory, rel, out, depth + 1);
        continue;
      }
      if (out.size() >= 4096)
        throw std::runtime_error("游戏存档文件数量超出限制");
      const uint64_t size = (static_cast<uint64_t>(entry.nFileSizeHigh) << 32) |
                            entry.nFileSizeLow;
      const uint64_t time =
          (static_cast<uint64_t>(entry.ftLastWriteTime.dwHighDateTime) << 32) |
          entry.ftLastWriteTime.dwLowDateTime;
      const int64_t millis =
          static_cast<int64_t>(time / 10000) - 11644473600000LL;
      out.push_back(V(M{{V("path"), V(Utf8(directory + L"\\" + rel))},
                        {V("directory"), V(Utf8(directory))},
                        {V("relativePath"), V(Utf8(rel))},
                        {V("size"), V(static_cast<int64_t>(size))},
                        {V("modifiedAt"), V(millis)}}));
    } while (FindNextFileW(search, &entry));
    const auto error = GetLastError();
    if (error != ERROR_NO_MORE_FILES)
      throw std::runtime_error("读取游戏存档列表未完成");
  } catch (...) {
    FindClose(search);
    throw;
  }
  FindClose(search);
}
L ListSaveFiles(DWORD pid) {
  L out;
  for (const auto &value : SaveFolders(pid)) {
    const auto &path = std::get<std::string>(value);
    CollectSaveFiles(Wide(path), L"", out, 0);
  }
  return out;
}

} // namespace
std::unique_ptr<flutter::MethodChannel<V>>
RegisterGameBridge(flutter::BinaryMessenger *messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<V>>(
      messenger, "pvz_formation_editor/game",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<V> &call,
         std::unique_ptr<flutter::MethodResult<V>> result) {
        try {
          if (call.method_name() == "listGames") {
            L games;
            EnumWindows(Discover, reinterpret_cast<LPARAM>(&games));
            result->Success(V(games));
            return;
          }
          if (call.method_name() == "applyFormation" ||
              call.method_name() == "saveFolders" ||
              call.method_name() == "listSaveFiles") {
            if (!call.arguments())
              throw std::runtime_error("缺少游戏参数");
            const auto &args = Object(*call.arguments());
            const int pid = Number(args, "pid");
            if (pid <= 0)
              throw std::runtime_error("游戏进程无效");
            if (call.method_name() == "saveFolders")
              result->Success(V(SaveFolders(static_cast<DWORD>(pid))));
            else if (call.method_name() == "listSaveFiles")
              result->Success(V(ListSaveFiles(static_cast<DWORD>(pid))));
            else
              result->Success(V(ApplyBoard(
                  static_cast<DWORD>(pid), Object(Field(args, "target")),
                  Object(Field(args, "expectedBefore")))));
            return;
          }
          if (call.method_name() == "readFormation") {
            const auto *args =
                call.arguments() ? std::get_if<M>(call.arguments()) : nullptr;
            if (!args)
              throw std::runtime_error("缺少游戏进程");
            auto it = args->find(V("pid"));
            if (it == args->end())
              throw std::runtime_error("缺少游戏进程");
            int64_t pid = 0;
            if (auto n = std::get_if<int32_t>(&it->second))
              pid = *n;
            else if (auto n = std::get_if<int64_t>(&it->second))
              pid = *n;
            if (pid <= 0 || pid > MAXDWORD)
              throw std::runtime_error("游戏进程无效");
            result->Success(V(ReadBoard(static_cast<DWORD>(pid))));
            return;
          }
          result->NotImplemented();
        } catch (const std::exception &e) {
          std::string message = e.what();
          if (blockedPid.load() != 0)
            message += "；游戏主循环恢复未能确认，请保留备份并重新启动游戏";
          result->Error("game_unavailable", message);
        }
      });
  return channel;
}
