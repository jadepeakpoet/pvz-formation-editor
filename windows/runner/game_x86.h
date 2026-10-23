#ifndef RUNNER_GAME_X86_H_
#define RUNNER_GAME_X86_H_
#include <cstddef>
#include <cstdint>
#include <vector>
struct GameX86 {
  std::vector<uint8_t> bytes;
  struct Fixup {
    size_t offset;
    uint32_t target;
  };
  std::vector<Fixup> calls;
  void Byte(uint8_t b) { bytes.push_back(b); }
  void Dword(uint32_t n) {
    for (int i = 0; i < 4; i++)
      Byte(static_cast<uint8_t>(n >> (i * 8)));
  }
  void Push(uint32_t n) {
    Byte(0x68);
    Dword(n);
  }
  void MovEax(uint32_t n) {
    Byte(0xb8);
    Dword(n);
  }
  void Call(uint32_t address) {
    Byte(0xe8);
    calls.push_back({bytes.size(), address});
    Dword(0);
  }
  void Relocate(uint32_t base) {
    for (const auto &call : calls) {
      const uint32_t relative =
          call.target - (base + static_cast<uint32_t>(call.offset) + 4);
      for (int i = 0; i < 4; i++)
        bytes[call.offset + i] = static_cast<uint8_t>(relative >> (8 * i));
    }
  }
};
#endif
