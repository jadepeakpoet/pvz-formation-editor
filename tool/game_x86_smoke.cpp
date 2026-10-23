#include "game_pe.h"
#include "game_x86.h"
#include <cassert>
#include <cstring>
#include <iostream>
uint32_t Decode(const std::vector<uint8_t> &b, size_t at) {
  return uint32_t(b.at(at)) | (uint32_t(b.at(at + 1)) << 8) |
         (uint32_t(b.at(at + 2)) << 16) | (uint32_t(b.at(at + 3)) << 24);
}
void CheckPeEntries() {
  std::vector<uint8_t> image(1024, 0);
  auto put = [&](size_t at, uint32_t value, size_t size) {
    for (size_t i = 0; i < size; i++)
      image.at(at + i) = static_cast<uint8_t>(value >> (8 * i));
  };
  put(0, 0x5a4d, 2);
  put(60, 0x80, 4);
  put(0x80, 0x4550, 4);
  put(0x84, 0x14c, 2);
  put(0x86, 1, 2);
  put(0x88, 0x49ecf563, 4);
  put(0x94, 224, 2);
  put(0x98, 0x10b, 2);
  put(0xb4, 0x400000, 4);
  const size_t section = 0x80 + 24 + 224;
  put(section + 12, 0x1000, 4);
  put(section + 16, 0x100000, 4);
  put(section + 20, 0x400, 4);
  put(section + 36, 0x20000000, 4);
  size_t cursor = 0;
  std::vector<uint64_t> reads;
  auto readAt = [&](uint64_t at, void *out, size_t size) {
    reads.push_back(at);
    if (at + size > image.size())
      return false;
    cursor = static_cast<size_t>(at);
    memcpy(out, image.data() + cursor, size);
    cursor += size;
    return true;
  };
  uint64_t offset = 0;
  assert(GamePe1051EntryOffset(readAt, 0x40d120, 32, offset) &&
         offset == 0xc520);
  assert(cursor != 0);
  reads.clear();
  assert(GamePe1051EntryOffset(readAt, 0x4679b0, 32, offset) &&
         offset == 0x66db0);
  assert(reads.front() ==
         0); // Second check independently starts at DOS header.
  put(0x88, 0x4d02b058, 4);
  assert(!GamePe1051EntryOffset(readAt, 0x40d120, 32, offset));
  put(0x88, 0x49ecf563, 4);
  put(0x84, 0x8664, 2);
  assert(!GamePe1051EntryOffset(readAt, 0x40d120, 32, offset));
  put(0x84, 0x14c, 2);
  put(section + 36, 0x40000000, 4);
  assert(!GamePe1051EntryOffset(readAt, 0x40d120, 32, offset));
  put(section + 36, 0x20000000, 4);
  put(section + 16, 0x20, 4);
  assert(!GamePe1051EntryOffset(readAt, 0x40d120, 32, offset));
  std::cout << "PE1051 repeated positional reads, address mappings and "
               "incompatible version/machine/section rejection passed\n";
}
int main() {
  CheckPeEntries();
  GameX86 c;
  c.Byte(0x60);
  c.Push(0xffffffff);
  c.Push(16);
  c.MovEax(2);
  c.Push(4);
  c.Push(0x12345678);
  c.Call(0x40d120);
  c.Byte(0x61);
  c.Byte(0x31);
  c.Byte(0xc0);
  c.Byte(0xc2);
  c.Byte(4);
  c.Byte(0);
  c.Relocate(0x1000000);
  assert(c.bytes.size() == 37);
  assert(c.bytes[0] == 0x60);
  assert(c.bytes[1] == 0x68 && Decode(c.bytes, 2) == 0xffffffff);
  assert(c.bytes[6] == 0x68 && Decode(c.bytes, 7) == 16);
  assert(c.bytes[11] == 0xb8 && Decode(c.bytes, 12) == 2);
  assert(c.bytes[16] == 0x68 && Decode(c.bytes, 17) == 4);
  assert(c.bytes[21] == 0x68 && Decode(c.bytes, 22) == 0x12345678);
  assert(c.bytes[26] == 0xe8 &&
         uint32_t(0x1000000 + 31 + Decode(c.bytes, 27)) == 0x40d120);
  assert(c.bytes[31] == 0x61 && c.bytes[32] == 0x31 && c.bytes[33] == 0xc0 &&
         c.bytes[34] == 0xc2 && c.bytes[35] == 4 && c.bytes[36] == 0);
  GameX86 deletes;
  deletes.Push(0x01020304);
  deletes.Call(0x4679b0);
  deletes.Push(0x05060708);
  deletes.Call(0x4679b0);
  deletes.Relocate(0x2000000);
  assert(Decode(deletes.bytes, 1) == 0x01020304 &&
         Decode(deletes.bytes, 11) == 0x05060708);
  assert(uint32_t(0x2000000 + 10 + Decode(deletes.bytes, 6)) == 0x4679b0);
  assert(uint32_t(0x2000000 + 20 + Decode(deletes.bytes, 16)) == 0x4679b0);
  std::cout
      << "1051 x86 ABI operand order, row register, two relocation bases, "
         "removal calls and ret4 checks passed; no game execution\n";
}
