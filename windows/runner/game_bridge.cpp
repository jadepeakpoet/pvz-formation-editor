#include "game_bridge.h"
#include "game_pe.h"
#include "game_x86.h"
#include <algorithm>
#include <atomic>
#include <climits>
#include <cmath>
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
bool HasVisualState(int type) {
  return type==3 || type==4 || type==9 || type==23 || type==26 ||
         type==36 || type==46 || type==47;
}
int ReadVisualState(HANDLE process,uintptr_t plant,int type) {
  const int state=Read<int32_t>(process,plant+0x3c);
  if(type==47) return state==37 ? 0 : 1;
  if(type==4) return state==16 ? 1 : 0;
  if(type==9) return state==25 ? 1 : 0;
  if(type==26) return state==32 ? 1 : 0;
  const int health=Read<int32_t>(process,plant+0x40),maximum=Read<int32_t>(process,plant+0x44);
  return health<maximum/3 ? 2 : health<maximum*2/3 ? 1 : 0;
}
std::pair<int,int> VisualFrame(int type,int state,bool asleep) {
  if(type==47) return {0,state==0 ? 0 : 2};
  if(type==4) return {0,state};
  if(type==9) return {asleep ? 0 : 1,state==1 ? 2 : 0};
  if(type==26) return {state==1 ? 2 : 0,0};
  if(type==3) return {0,state==0 ? 0 : state+1};
  if(type==23 || type==36 || type==46) return {0,state};
  return {GameX86::Sleepable(type) && !asleep ? 1 : 0,0};
}
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
uintptr_t CobTrackColor(HANDLE process, uintptr_t animation) {
  const auto definition = Read<uint32_t>(process, animation + 0xc);
  const auto tracks = Read<uint32_t>(process, definition);
  const auto count = Read<uint32_t>(process, definition + 4);
  if (!tracks || count > 512)
    throw std::runtime_error("玉米炮动画轨道无效");
  for (uint32_t i = 0; i < count; ++i) {
    const auto name = Read<uint32_t>(process, tracks + i * 12);
    const char expected[] = "CobCannon_cob";
    bool match = true;
    for (size_t j = 0; j < sizeof(expected); ++j) {
      if (Read<char>(process, name + j) != expected[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      const auto instances = Read<uint32_t>(process, animation + 0x58);
      if (!instances) break;
      return instances + i * 0x60 + 0x4c;
    }
  }
  throw std::runtime_error("未找到玉米炮弹头动画轨道");
}
std::string ReadAscii(HANDLE process,uintptr_t address) {
  std::string result;
  for(int i=0;i<128;i++) {
    const auto c=Read<char>(process,address+i);
    if(!c) return result;
    result+=c;
  }
  throw std::runtime_error("动画轨道名称无效");
}
struct ZombieAnimation {
  uintptr_t address,tracks,instances;
  uint32_t count;
};
ZombieAnimation GetZombieAnimation(HANDLE process,uint32_t lawn,uint32_t zombie) {
  const auto id=Read<uint32_t>(process,zombie+0x118);
  const auto holder=Read<uint32_t>(process,lawn+0x820);
  const auto array=Read<uint32_t>(process,holder+8);
  const auto index=id&0xffff;
  if(!id || index>=Read<uint32_t>(process,array+8)) throw std::runtime_error("僵尸动画身份无效");
  const uintptr_t animation=Read<uint32_t>(process,array)+index*0xa0;
  if(Read<uint32_t>(process,animation+0x9c)!=id) throw std::runtime_error("僵尸动画身份已改变");
  const auto definition=Read<uint32_t>(process,animation+0xc);
  const auto count=Read<uint32_t>(process,definition+4);
  if(count>512) throw std::runtime_error("僵尸动画轨道无效");
  return {animation,Read<uint32_t>(process,definition),Read<uint32_t>(process,animation+0x58),count};
}
std::pair<int,int> AnimationRange(HANDLE process,uintptr_t track) {
  const auto transforms=Read<uint32_t>(process,track+4);
  const auto count=Read<uint32_t>(process,track+8);
  if(!transforms || count>4096) throw std::runtime_error("僵尸动画帧无效");
  std::vector<uint8_t> frames(static_cast<size_t>(count)*44);
  SIZE_T got=0;
  if(!ReadProcessMemory(process,reinterpret_cast<const void*>(static_cast<uintptr_t>(transforms)),frames.data(),frames.size(),&got) || got!=frames.size())
    throw std::runtime_error("无法读取僵尸动画帧");
  int start=-1,last=-1;
  for(uint32_t i=0;i<count;i++) {
    float frame;std::memcpy(&frame,frames.data()+i*44+24,sizeof(frame));
    if(frame>=0) {
    if(start<0) start=static_cast<int>(i);
    last=static_cast<int>(i);
    }
  }
  return {start,last-start+1};
}
M ReadZombieState(HANDLE process,uint32_t lawn,uint32_t zombie) {
  M state;
  for(const auto& field:std::vector<std::pair<const char*,uint32_t>>{
      {"phase",0x28},{"height",0x64},{"phaseCounter",0x68},
      {"helmetType",0xc4},{"bodyHealth",0xc8},{"bodyMaxHealth",0xcc},
      {"helmetHealth",0xd0},{"helmetMaxHealth",0xd4},{"shieldType",0xd8},
      {"shieldHealth",0xdc},{"shieldMaxHealth",0xe0},{"flyingHealth",0xe4}})
    state[V(field.first)]=V(Read<int32_t>(process,zombie+field.second));
  for(const auto& field:std::vector<std::pair<const char*,uint32_t>>{
      {"eating",0x51},{"hasHead",0xba},{"hasArm",0xbb},{"hasObject",0xbc},{"inPool",0xbd}})
    state[V(field.first)]=V(Read<uint8_t>(process,zombie+field.second)!=0);
  state[V("altitude")]=V(static_cast<double>(Read<float>(process,zombie+0x84)));
  const auto animation=GetZombieAnimation(process,lawn,zombie);
  state[V("renderOffsetY")]=V(static_cast<double>(Read<float>(process,animation.address+0x38)));
  const auto start=Read<int32_t>(process,animation.address+0x18);
  const auto count=Read<int32_t>(process,animation.address+0x1c);
  std::string name;
  L hidden;
  for(uint32_t i=0;i<animation.count;i++) {
    const auto track=animation.tracks+i*12;
    const auto trackName=ReadAscii(process,Read<uint32_t>(process,track));
    if(trackName.rfind("anim_",0)==0) {
      const auto range=AnimationRange(process,track);
      if(range.first==start && range.second==count && name.empty()) name=trackName;
    }
    if(Read<int32_t>(process,animation.instances+i*0x60+0x48)==-1)
      hidden.emplace_back(trackName);
  }
  state[V("animation")]=V(name);
  state[V("bodyFrameStart")]=V(start);state[V("bodyFrameCount")]=V(count);
  state[V("hiddenTracks")]=V(hidden);
  return state;
}
M ReadBoard(DWORD pid,bool includeZombies=false) {
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
    const bool asleep=Read<uint8_t>(p.h,a+0x143)!=0;
    const int visualState=HasVisualState(type) ? ReadVisualState(p.h,a,type) : 0;
    const auto frame=VisualFrame(type,visualState,asleep);
    M piece{{V("type"), V(type)},
            {V("row"), V(row)},
            {V("col"), V(col)},
            {V("imitater"), V(Read<int32_t>(p.h, a + 0x138) == 48)},
            {V("asleep"), V(asleep)},
            {V("frameRow"), V(frame.first)},
            {V("frameCol"), V(frame.second)}};
    if(HasVisualState(type)) piece[V("visualState")]=V(visualState);
    const int eatenFlash=Read<int32_t>(p.h,a+0xb8);
    if(eatenFlash>0) piece[V("eatenFlashCountdown")]=V(eatenFlash);
    if(type==47) {
      piece[V("plantState")]=V(Read<int32_t>(p.h,a+0x3c));
      piece[V("stateCountdown")]=V(Read<int32_t>(p.h,a+0x54));
      const uint32_t id=Read<uint32_t>(p.h,a+0x94);
      const uint32_t holder=Read<uint32_t>(p.h,lawn+0x820);
      const uint32_t array=Read<uint32_t>(p.h,holder+8);
      const uint32_t index=id&0xffff;
      if(id && index<Read<uint32_t>(p.h,array+8)) {
        const uintptr_t animation=Read<uint32_t>(p.h,array)+index*0xa0;
        if(Read<uint32_t>(p.h,animation+0x9c)==id) {
          piece[V("bodyFrameStart")]=V(Read<int32_t>(p.h,animation+0x18));
          piece[V("bodyFrameCount")]=V(Read<int32_t>(p.h,animation+0x1c));
          const auto color = CobTrackColor(p.h, animation);
          piece[V("cobBrightness")]=V(Read<int32_t>(p.h,color));
        }
      }
    }
    pieces.push_back(V(piece));
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
  if(includeZombies) {
    const auto zombies=Read<uint32_t>(p.h,board+0x90), capacity=Read<uint32_t>(p.h,board+0x94);
    if(capacity>4096 || (capacity && !zombies)) throw std::runtime_error("僵尸数组无效");
    for(uint32_t i=0;i<capacity;i++) {
      const uintptr_t a=zombies+i*0x15c;
      if(Read<uint8_t>(p.h,a+0xec)) continue;
      const int type=Read<int32_t>(p.h,a+0x24), row=Read<int32_t>(p.h,a+0x1c);
      const float x=Read<float>(p.h,a+0x2c)+40.0f;
      if(type<0 || type>32 || row<0 || row>5 || !std::isfinite(x) || x< -200 || x>1200)
        throw std::runtime_error("僵尸类型或坐标无效");
      const int phase=Read<int32_t>(p.h,a+0x28);
      const int col=std::clamp(static_cast<int>(std::floor((x-40.0f)/80.0f)),0,8);
      int fr=0,fc=0;
      if(type==14 && (phase==53 || phase==55)) { fr=1; fc=phase==55 ? 2 : 1; }
      M zombie{{V("zombieType"),V(type)},{V("row"),V(row)},{V("col"),V(col)},
          {V("x"),V(static_cast<double>(x))},{V("phase"),V(phase)},
          {V("frameRow"),V(fr)},{V("frameCol"),V(fc)}};
      const auto state=ReadZombieState(p.h,lawn,static_cast<uint32_t>(a));
      zombie.insert(state.begin(),state.end());
      pieces.emplace_back(zombie);
    }
  }
  if (Read<uint32_t>(p.h, lawn + 0x768) != board)
    throw std::runtime_error("读取期间场景发生变化，请重试");
  return M{{V("pid"), V(static_cast<int64_t>(pid))},
           {V("version"), V("1.0.0.1051 en")},
           {V("map"), V(maps[scene])},
           {V("sunValue"), V(Read<int32_t>(p.h, board + 0x5560))},
           {V("pieces"), V(pieces)}, {V("includeZombies"),V(includeZombies)}};
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
bool RuntimeEntryCompatible(HANDLE process, uint32_t address) {
  MEMORY_BASIC_INFORMATION region{};
  if (!VirtualQueryEx(process, reinterpret_cast<LPCVOID>(static_cast<uintptr_t>(address)),
                      &region, sizeof(region)) || region.State != MEM_COMMIT ||
      region.Type != MEM_IMAGE || reinterpret_cast<uintptr_t>(region.AllocationBase) != 0x400000 ||
      (region.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
  const DWORD protection = region.Protect & 0xff;
  if (protection != PAGE_EXECUTE && protection != PAGE_EXECUTE_READ &&
      protection != PAGE_EXECUTE_READWRITE && protection != PAGE_EXECUTE_WRITECOPY) return false;
  uint8_t entry[16]{};
  SIZE_T count=0;
  return ReadProcessMemory(process, reinterpret_cast<LPCVOID>(static_cast<uintptr_t>(address)),
                           entry, sizeof(entry), &count) && count==sizeof(entry) &&
         entry[0]!=0 && entry[0]!=0xcc && entry[0]!=0xe9 && entry[0]!=0xeb && entry[0]!=0xc3;
}
bool WriteCompatible(HANDLE process, const std::string &) {
  try {
    if (Read<uint8_t>(process, 0x552014) != 0xdb) return false;
    // Like Toolkit, identify the loaded game instead of reopening its DRM-locked EXE.
    for (uint32_t address : {0x40d120u,0x4679b0u,0x45e860u,0x40a160u,
                              0x458d10u,0x40bc70u,0x5160c0u,0x466b80u,
                              0x408f40u,0x426620u,0x44d000u,0x40bb2cu,0x41e1c0u,
                              0x45fd90u}) {
      if (!RuntimeEntryCompatible(process,address)) return false;
    }
    return true;
  } catch (...) { return false; }
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
double Real(const M& value,const char* key) {
  const auto& v=Field(value,key);
  double result;
  if(const auto p=std::get_if<double>(&v)) result=*p;
  else result=Number(value,key);
  if(!std::isfinite(result)) throw std::runtime_error("无效浮点坐标");
  return result;
}
void RequireRepresentable(const M &snapshot) {
  const auto &map = std::get<std::string>(Field(snapshot, "map"));
  if(map!="day" && map!="night" && map!="pool" && map!="fog" && map!="roof" && map!="moonRoof")
    throw std::runtime_error("当前阵型使用扩展地图；原版游戏仅支持六种标准场地");
  const auto &pieces = std::get<L>(Field(snapshot, "pieces"));
  if (pieces.size() > 512)
    throw std::runtime_error("当前一次最多应用512个植物");
  for (const auto &item : pieces) {
    const auto &p = Object(item);
    if(p.find(V("zombieType"))!=p.end()) {
      const int type=Number(p,"zombieType"),row=Number(p,"row"),col=Number(p,"col");
      const double x=Real(p,"x");
      if(!Flag(snapshot,"includeZombies") || type<0 || type>24 || type==10 || type==12 || type==13 || type==20 ||
          row<0 || row>(map=="pool" || map=="fog" ? 5 : 4) || col<0 || col>8 || x< -200 || x>1200)
        throw std::runtime_error("僵尸类型或坐标尚不支持");
      const auto& state=Object(Field(p,"state"));
      const auto& animation=std::get<std::string>(Field(state,"animation"));
      const int phase=Number(state,"phase");
      if(animation.rfind("anim_",0)!=0 || animation.size()>32 || phase<0 || phase>77)
        throw std::runtime_error("僵尸外观状态无效");
      if(state.find(V("altitude"))!=state.end() && (Real(state,"altitude")< -150 || Real(state,"altitude")>1000))
        throw std::runtime_error("僵尸高度无效");
      continue;
    }
    if (p.find(V("gridType")) != p.end()) {
      const int kind=Number(p,"gridType"), row=Number(p,"row"), col=Number(p,"col");
      if((kind!=1 && kind!=3 && kind!=11) || row<0 || row>(map=="pool" || map=="fog" ? 5 : 4) || col<0 || col>8 || Flag(p,"imitater"))
        throw std::runtime_error("道具类型、位置或模仿者标志无效");
      continue;
    }
    const int type = Number(p, "type"), row = Number(p, "row"),
              col = Number(p, "col");
    if (type < 0 || type > 47 || row < 0 ||
        row > (map == "pool" || map == "fog" ? 5 : 4) || col < 0 || col > 8)
      throw std::runtime_error("阵型植物或坐标超出原版场地");
    if(p.find(V("visualState"))!=p.end()) {
      const int state=Number(p,"visualState");
      if(!HasVisualState(type) || state<0 || state>((type==3 || type==23 || type==36 || type==46) ? 2 : 1))
        throw std::runtime_error("植物外观对应的游戏状态无效");
    }


  }
}

std::vector<std::tuple<int, int, int, bool, bool, int>>
Composition(const M &snapshot) {
  std::vector<std::tuple<int, int, int, bool, bool, int>> value;
  for (const auto &p : std::get<L>(Field(snapshot, "pieces"))) {
    const auto &m = Object(p);
    if(m.find(V("zombieType"))!=m.end()) {
      value.emplace_back(100+Number(m,"zombieType"),Number(m,"row"),Number(m,"col"),false,false,
          static_cast<int>(std::lround(Real(m,"x")*4)));
      continue;
    }
    value.emplace_back(m.find(V("gridType"))==m.end() ? Number(m,"type") : 48+Number(m,"gridType"), Number(m, "row"), Number(m, "col"),
                       Flag(m, "imitater"), Flag(m, "asleep"),0);
  }
  std::sort(value.begin(), value.end());
  return value;
}
void VerifyVisualStates(const M &target,const M &actual) {
  const auto& results=std::get<L>(Field(actual,"pieces"));
  for(const auto& item:std::get<L>(Field(target,"pieces"))) {
    const auto& expected=Object(item);
    const bool visual=expected.find(V("visualState"))!=expected.end();
    const bool flash=Flag(expected,"eatenFlash");
    if(!visual && !flash) continue;
    bool found=false;
    for(const auto& candidate:results) {
      const auto& p=Object(candidate);
      if(p.find(V("type"))==p.end() || Number(p,"type")!=Number(expected,"type") ||
          Number(p,"row")!=Number(expected,"row") || Number(p,"col")!=Number(expected,"col")) continue;
      found=(!visual || (p.find(V("visualState"))!=p.end() && Number(p,"visualState")==Number(expected,"visualState"))) &&
          (!flash || (p.find(V("eatenFlashCountdown"))!=p.end() && Number(p,"eatenFlashCountdown")>0));
      break;
    }
    if(!found) throw std::runtime_error("植物外观对应的状态校验不一致，请重新获取阵型");
  }
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
template<class T> void Store(HANDLE process,uintptr_t address,T value) {
  WriteBytes(process,address,&value,sizeof(value));
}
void SetZombieState(HANDLE process,uint32_t lawn,uint32_t zombie,const M& state) {
  const auto animation=GetZombieAnimation(process,lawn,zombie);
  const auto& name=std::get<std::string>(Field(state,"animation"));
  std::pair<int,int> range{-1,0};
  std::vector<std::string> hidden;
  for(const auto& prefix:std::get<L>(Field(state,"hidden"))) {
    const auto& text=std::get<std::string>(prefix);
    if(text.size()>64 || text.rfind("Zombie_",0)!=0) throw std::runtime_error("僵尸携带物图层无效");
    hidden.push_back(text);
  }
  const int type=Read<int32_t>(process,zombie+0x24);
  if(!Flag(state,"hasArm")) {
    if(type==7) { hidden.push_back("Zombie_football_leftarm_lower");hidden.push_back("Zombie_football_leftarm_hand"); }
    else if(type==5) { hidden.push_back("Zombie_paper_hands");hidden.push_back("Zombie_paper_leftarm_lower"); }
    else { hidden.push_back("Zombie_outerarm_lower");hidden.push_back("Zombie_outerarm_hand"); }
  }
  const bool removeShield=state.find(V("shieldType"))!=state.end() && Number(state,"shieldType")==0;
  for(uint32_t i=0;i<animation.count;i++) {
    const auto track=animation.tracks+i*12;
    const auto trackName=ReadAscii(process,Read<uint32_t>(process,track));
    if(trackName==name) range=AnimationRange(process,track);
    const auto instance=animation.instances+i*0x60;
    if(type==5 && Number(state,"phase")==31 && trackName=="anim_head1")
      Store<uint32_t>(process,instance+0x44,Read<uint32_t>(process,0x6a7b34));
    if(removeShield && Read<int32_t>(process,instance+0x48)==1)
      Store<int32_t>(process,instance+0x48,-1);
    if(removeShield && (trackName.rfind("Zombie_paper_hands",0)==0 || trackName.rfind("Zombie_outerarm",0)==0))
      Store<int32_t>(process,instance+0x48,0);
    for(const auto& prefix:hidden) if(trackName.rfind(prefix,0)==0)
      Store<int32_t>(process,instance+0x48,-1);
    // A newly selected appearance starts immediately, without the constructor's blend.
    Store<int32_t>(process,instance,0);Store<int32_t>(process,instance+4,0);
  }
  if(range.first<0 || range.second<1) throw std::runtime_error("游戏缺少所选僵尸动画轨道");
  Store<int32_t>(process,zombie+0x28,Number(state,"phase"));
  Store<uint8_t>(process,zombie+0x51,Flag(state,"eating") ? 1 : 0);
  Store<uint8_t>(process,zombie+0xbb,Flag(state,"hasArm") ? 1 : 0);
  Store<uint8_t>(process,zombie+0xbd,Flag(state,"inPool") ? 1 : 0);
  Store<int32_t>(process,zombie+0x64,0);
  if(state.find(V("hasObject"))!=state.end()) Store<uint8_t>(process,zombie+0xbc,Flag(state,"hasObject") ? 1 : 0);
  if(state.find(V("altitude"))!=state.end()) Store<float>(process,zombie+0x84,static_cast<float>(Real(state,"altitude")));
  if(state.find(V("flyingHealth"))!=state.end()) Store<int32_t>(process,zombie+0xe4,Number(state,"flyingHealth"));
  if(removeShield) { Store<int32_t>(process,zombie+0xd8,0);Store<int32_t>(process,zombie+0xdc,0); }
  if(!Flag(state,"hasArm")) Store<int32_t>(process,zombie+0xc8,Read<int32_t>(process,zombie+0xcc)/2);
  if(Number(state,"phase")==0) Store<int32_t>(process,zombie+0x68,0);
  if(Number(state,"phase")==40 || Number(state,"phase")==67) Store<int32_t>(process,zombie+0x68,300);
  if(Number(state,"phase")==20) Store<int32_t>(process,zombie+0x68,80);
  if(type==14 && Flag(state,"inPool")) {
    const int32_t rect[]={20,0,42,115}, attack[]={30,0,30,115};
    WriteBytes(process,zombie+0x8c,rect,sizeof(rect));WriteBytes(process,zombie+0x9c,attack,sizeof(attack));
  }
  Store<int32_t>(process,animation.address+0x18,range.first);
  Store<int32_t>(process,animation.address+0x1c,range.second);
  Store<float>(process,animation.address+4,0);
  Store<float>(process,animation.address+8,Flag(state,"eating") ? 20.0f : 12.0f);
  Store<int32_t>(process,animation.address+0x10,0);
  Store<int32_t>(process,animation.address+0x5c,0);
  Store<float>(process,animation.address+0x94,-1.0f);
  Store<float>(process,zombie+0x124,Flag(state,"eating") ? 20.0f : 12.0f);
  const auto actual=ReadZombieState(process,lawn,zombie);
  for(const auto& key:{"animation","phase","eating","inPool","hasArm","hasObject","shieldType","flyingHealth","altitude"}) {
    const auto expected=state.find(V(key));
    if(expected==state.end()) continue;
    bool same;
    if(const auto value=std::get_if<std::string>(&expected->second)) same=std::get<std::string>(actual.at(V(key)))==*value;
    else if(const auto boolean=std::get_if<bool>(&expected->second)) same=Flag(actual,key)==*boolean;
    else same=Real(actual,key)==Real(state,key);
    if(!same) throw std::runtime_error(std::string("僵尸状态读回不一致：")+key);
  }
  const auto& actualHidden=std::get<L>(actual.at(V("hiddenTracks")));
  for(const auto& prefix:hidden) for(uint32_t i=0;i<animation.count;i++) {
    const auto trackName=ReadAscii(process,Read<uint32_t>(process,animation.tracks+i*12));
    if(trackName.rfind(prefix,0)==0 && std::find(actualHidden.begin(),actualHidden.end(),V(trackName))==actualHidden.end())
      throw std::runtime_error("僵尸携带物图层读回不一致");
  }
}
void ApplyZombieStates(HANDLE process,uint32_t lawn,uint32_t board,const L& pieces) {
  const auto array=Read<uint32_t>(process,board+0x90), count=Read<uint32_t>(process,board+0x94);
  if(count>4096) throw std::runtime_error("应用后僵尸数组无效");
  std::vector<uint32_t> used;
  for(const auto& item:pieces) {
    const auto& target=Object(item);
    if(target.find(V("zombieType"))==target.end()) continue;
    uint32_t match=0;
    for(uint32_t i=0;i<count;i++) {
      const auto zombie=array+i*0x15c;
      if(Read<uint8_t>(process,zombie+0xec) || std::find(used.begin(),used.end(),zombie)!=used.end()) continue;
      if(Read<int32_t>(process,zombie+0x24)==Number(target,"zombieType") && Read<int32_t>(process,zombie+0x1c)==Number(target,"row") &&
          std::lround((Read<float>(process,zombie+0x2c)+40)*4)==std::lround(Real(target,"x")*4)) { match=zombie;break; }
    }
    if(!match) throw std::runtime_error("未找到刚应用的僵尸");
    SetZombieState(process,lawn,match,Object(Field(target,"state")));used.push_back(match);
  }
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
          "上次游戏主循环恢复未能确认，请先重新启动游戏；请重新获取阵型");
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
    throw std::runtime_error("当前原版1051的运行内存或调用入口校验未通过");
  RequireRepresentable(target);
  const bool includeZombies=Flag(target,"includeZombies");
  if(includeZombies) {
    for(uint32_t address:{0x40ddc0u,0x530510u,0x52f2e0u,0x528b00u,0x52c310u})
      if(!RuntimeEntryCompatible(process.h,address)) throw std::runtime_error("僵尸函数入口校验失败");
  }
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
  const M before = ReadBoard(pid,includeZombies);
  if (std::get<std::string>(Field(before, "map")) !=
          std::get<std::string>(Field(expected, "map")) ||
      Composition(before) != Composition(expected) ||
      Number(before, "sunValue") != Number(expected, "sunValue"))
    throw std::runtime_error(
        "游戏阵型在读取后发生变化，请重新获取后重试");
  const int sun = Number(target, "sunValue");
  if (sun < 0 || sun > 999999)
    throw std::runtime_error("目标阳光值无效");
  X86 code;
  code.Byte(0x60); // Preserve registers for the remote thread entry.
  if(includeZombies) {
    const auto zombies=Read<uint32_t>(process.h,board+0x90),capacity=Read<uint32_t>(process.h,board+0x94);
    if(capacity>4096 || (capacity && !zombies)) throw std::runtime_error("僵尸数组无效");
    for(uint32_t i=0;i<capacity;i++) {
      const uint32_t address=zombies+i*0x15c;
      if(!Read<uint8_t>(process.h,address+0xec)) code.RemoveZombie(address);
    }
  }
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
  const auto grids=Read<uint32_t>(process.h,board+0x11c), gridCount=Read<uint32_t>(process.h,board+0x120);
  if(gridCount>4096 || (gridCount && !grids)) throw std::runtime_error("道具数组无效");
  for(uint32_t i=0;i<gridCount;i++) {
    const uint32_t address=grids+i*0xec;
    const int kind=Read<int32_t>(process.h,address+8);
    if(!Read<uint8_t>(process.h,address+0x20) && (kind==1 || kind==3 || kind==11)) {
      code.Byte(0xbe); code.Dword(address); code.Call(0x44d000);
    }
  }
  const auto targetMap = std::get<std::string>(Field(target,"map"));
  const char* maps[] = {"day","night","pool","fog","roof","moonRoof"};
  int targetScene=-1;
  for (int i=0;i<6;i++) if (targetMap==maps[i]) targetScene=i;
  if(targetScene<0) throw std::runtime_error("目标场地尚未适配");
  const bool changeScene = targetMap != std::get<std::string>(Field(before,"map"));
  if (changeScene) {
    const auto mowers=Read<uint32_t>(process.h,board+0x100);
    const auto mowerCapacity=Read<uint32_t>(process.h,board+0x104);
    if(mowerCapacity>4096 || (mowerCapacity && !mowers))
      throw std::runtime_error("小推车数组无效，未修改游戏");
    bool hadMowers=false;
    for(uint32_t i=0;i<mowerCapacity;i++) {
      const auto address=mowers+i*0x48;
      if(!Read<uint8_t>(process.h,address+0x30)) {
        hadMowers=true; code.MovEax(address); code.Call(0x458d10);
      }
    }
    code.StoreDword(board+0x554c,static_cast<uint32_t>(targetScene));
    code.Byte(0xbe); code.Dword(board); // PickBackground receives Board in ESI.
    code.Call(0x40a160);
    const bool pool=targetScene==2 || targetScene==3;
    for(uint32_t row=0;row<6;row++) {
      const uint32_t rowType=pool ? ((row==2 || row==3) ? 2u : 1u) : (row==5 ? 0u : 1u);
      code.StoreDword(board+0x5d8+row*4,rowType);
      for(uint32_t col=0;col<9;col++)
        code.StoreDword(board+0x168+(col*6+row)*4,pool && (row==2 || row==3) ? 3u : (!pool && row==5 ? 2u : 1u));
    }
    if(hadMowers) { code.MovEax(board); code.Push(board); code.Call(0x40bc70); }
    if(!pool) {
      const auto animations=Read<uint32_t>(process.h,lawn+0x820);
      const auto systems=Read<uint32_t>(process.h,animations);
      const auto particles=Read<uint32_t>(process.h,systems);
      const auto capacity=Read<uint32_t>(process.h,systems+4);
      if(capacity>65536 || (capacity && !particles))
        throw std::runtime_error("场景粒子数组无效，未修改游戏");
      for(uint32_t i=0;i<capacity;i++) {
        const auto address=particles+i*0x2c;
        if(!Read<uint8_t>(process.h,address+0x1c) && Read<int32_t>(process.h,address)==34) {
          code.Push(address); code.Call(0x5160c0);
        }
      }
      code.StoreDword(board+0x5620,0);
    }
  }
  auto pieces = std::get<L>(Field(target, "pieces"));
  auto order = [](int type) {
    return type == 16 || type == 33 ? 0 : type == 30 ? 2 : type == 35 ? 3 : 1;
  };
  std::stable_sort(pieces.begin(), pieces.end(), [&](const V &a, const V &b) {
    const auto rank=[&](const V& value) { const auto& p=Object(value);
      if(p.find(V("zombieType"))!=p.end()) return 5;
      return p.find(V("gridType"))!=p.end() ? 4 : order(Number(p,"type")); };
    return rank(a)<rank(b);
  });
  for (const auto &item : pieces) {
    const auto &p = Object(item);
    if(p.find(V("zombieType"))!=p.end()) {
      code.PutZombie(board,Number(p,"row"),Number(p,"zombieType"),
          static_cast<float>(Real(p,"x")),targetScene==2 || targetScene==3,
          Number(p,"frameRow"),Number(p,"frameCol"));
      if(Number(p,"zombieType")==14 && Number(p,"frameRow")==1 &&
          (Number(p,"frameCol")==2 || Number(p,"frameCol")==4))
        code.InitializeDolphinPose(Flag(Object(Field(p,"state")),"eating"));
    } else if(p.find(V("gridType"))!=p.end()) {
      const int kind=Number(p,"gridType");
      code.Byte(0xbf); code.Dword(static_cast<uint32_t>(Number(p,"row")));
      if(kind==3) {
        code.Push(static_cast<uint32_t>(Number(p,"col"))); code.MovEax(board); code.Call(0x408f40);
      } else if(kind==1) {
        code.Byte(0xbb); code.Dword(static_cast<uint32_t>(Number(p,"col")));
        code.Push(Read<uint32_t>(process.h,board+0x160)); code.Call(0x426620);
      } else {
        code.PutRake(board,Number(p,"row"),Number(p,"col"));
      }
    } else {
      code.PutPlant(board,Number(p,"row"),Number(p,"col"),Number(p,"type"),
                    Flag(p,"asleep"),targetScene==0 || targetScene==2 || targetScene==4,Flag(p,"imitater"),
                    p.find(V("visualState"))==p.end() ? 0 : Number(p,"visualState"));
      if(Flag(p,"eatenFlash")) code.EaxField(0xb8,25);
    }
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
      throw std::runtime_error("游戏调用超时，可能已部分应用；请重新获取阵型，后台"
                               "等待调用结束后恢复主循环");
    }
    DWORD exit = 0;
    if (!GetExitCodeThread(thread, &exit) || exit != 0)
      throw std::runtime_error(
          "游戏构造函数异常退出，可能已部分应用；请重新获取并注入阵型");
    if(includeZombies) ApplyZombieStates(process.h,lawn,board,pieces);
    WriteBytes(process.h, board + 0x5560, &sun, sizeof(sun));
    // Start loaded cannons at the bright end of their normal ready pulse.
    // The game's own subsequent updates retain the original flashing behavior.
    const auto plantArray = Read<uint32_t>(process.h, board + 0xac);
    const auto plantCount = Read<uint32_t>(process.h, board + 0xb0);
    if (plantCount > 4096)
      throw std::runtime_error("应用后植物数组无效");
    const auto holder = Read<uint32_t>(process.h, lawn + 0x820);
    const auto animations = Read<uint32_t>(process.h, holder + 8);
    for (uint32_t i = 0; i < plantCount; ++i) {
      const uintptr_t plant = plantArray + i * 0x14c;
      if (Read<uint8_t>(process.h, plant + 0x141) ||
          Read<uint8_t>(process.h, plant + 0x142) ||
          Read<int32_t>(process.h, plant + 0x24) != 47 ||
          Read<int32_t>(process.h, plant + 0x3c) != 37) continue;
      const auto id = Read<uint32_t>(process.h, plant + 0x94);
      const auto index = id & 0xffff;
      if (!id || index >= Read<uint32_t>(process.h, animations + 8))
        throw std::runtime_error("玉米炮动画身份无效");
      const uintptr_t animation = Read<uint32_t>(process.h, animations) + index * 0xa0;
      if (Read<uint32_t>(process.h, animation + 0x9c) != id)
        throw std::runtime_error("玉米炮动画身份不一致");
      const int32_t white[] = {255, 255, 255, 255};
      WriteBytes(process.h, CobTrackColor(process.h, animation), white, sizeof(white));
    }
    CloseHandle(thread);
    thread = nullptr;
    VirtualFreeEx(process.h, allocation, 0, MEM_RELEASE);
    allocation = nullptr;
    const M after = ReadBoard(pid,includeZombies);
    VerifyVisualStates(target,after);
    if (std::get<std::string>(Field(after,"map")) != targetMap ||
        Composition(after) != Composition(target) ||
        Number(after, "sunValue") != Number(target, "sunValue"))
      throw std::runtime_error(
          "应用后阵型校验不一致，可能已部分应用；请重新获取并注入阵型");
    if (!loop.Restore())
      throw std::runtime_error(
          "阵型已应用但主循环恢复校验失败，请重新启动游戏");
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
            else if (auto widePid = std::get_if<int64_t>(&it->second))
              pid = *widePid;
            if (pid <= 0 || pid > MAXDWORD)
              throw std::runtime_error("游戏进程无效");
            result->Success(V(ReadBoard(static_cast<DWORD>(pid),Flag(*args,"includeZombies"))));
            return;
          }
          result->NotImplemented();
        } catch (const std::exception &e) {
          std::string message = e.what();
          if (blockedPid.load() != 0)
            message += "；游戏主循环恢复未能确认，请重新启动游戏";
          result->Error("game_unavailable", message);
        }
      });
  return channel;
}
