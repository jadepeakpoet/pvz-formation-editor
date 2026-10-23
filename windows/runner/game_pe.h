#ifndef RUNNER_GAME_PE_H_
#define RUNNER_GAME_PE_H_
#include <cstddef>
#include <cstdint>
#include <vector>
// ReadAt is positional: repeated entry checks cannot inherit a previous cursor.
template <class ReadAt>
bool GamePe1051EntryOffset(ReadAt readAt, uint32_t address, size_t length,
                           uint64_t &offset) {
  auto word = [](const uint8_t *p) {
    return uint16_t(p[0]) | (uint16_t(p[1]) << 8);
  };
  auto dword = [](const uint8_t *p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) |
           (uint32_t(p[3]) << 24);
  };
  uint8_t dos[64]{};
  if (!readAt(0, dos, sizeof(dos)) || word(dos) != 0x5a4d)
    return false;
  uint32_t pe = dword(dos + 60);
  if (pe < 64 || pe > 1048576)
    return false;
  uint8_t nt[56]{};
  if (!readAt(pe, nt, sizeof(nt)) || dword(nt) != 0x4550 ||
      word(nt + 4) != 0x14c || dword(nt + 8) != 0x49ecf563 ||
      word(nt + 24) != 0x10b || dword(nt + 52) != 0x400000)
    return false;
  const auto sections = word(nt + 6), optionalSize = word(nt + 20);
  if (sections == 0 || sections > 96 || optionalSize < 96 ||
      optionalSize > 4096 || address < 0x400000 || length > 4096)
    return false;
  const uint64_t rva = address - 0x400000;
  for (uint16_t i = 0; i < sections; i++) {
    uint8_t section[40]{};
    if (!readAt(uint64_t(pe) + 24 + optionalSize + uint64_t(i) * 40, section,
                40))
      return false;
    const uint64_t va = dword(section + 12), rawSize = dword(section + 16),
                   rawOffset = dword(section + 20);
    if (!(dword(section + 36) & 0x20000000) || rva < va ||
        rva + length > va + rawSize)
      continue;
    offset = rawOffset + rva - va;
    return true;
  }
  return false;
}
#endif
