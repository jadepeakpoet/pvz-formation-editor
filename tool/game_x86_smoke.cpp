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
  GameX86 zombie;
  zombie.PutZombie(0x12345678,2,14,287.0f,true,1,2);
  assert(Decode(zombie.bytes,1)==2 && Decode(zombie.bytes,6)==14);
  assert(zombie.calls.size()==2 && zombie.calls[0].target==0x40ddc0 &&
         zombie.calls[1].target==0x52f2e0);
  zombie.Relocate(0x2000000);
  const auto walk=zombie.calls[1].offset;
  assert(zombie.bytes[walk-3]==0x31 && zombie.bytes[walk-2]==0xf6);
  for(const auto& fixup:zombie.calls)
    assert(uint32_t(0x2000000+fixup.offset+4+Decode(zombie.bytes,fixup.offset))==fixup.target);
  GameX86 zombieDelete;
  GameX86 eatingDolphin;
  eatingDolphin.InitializeDolphinPose(true);
  assert(eatingDolphin.calls.size()==2 && eatingDolphin.calls[0].target==0x528b00 &&
         eatingDolphin.calls[1].target==0x52c310);
  assert(eatingDolphin.bytes[0]==0xc6 && eatingDolphin.bytes[1]==0x80 &&
         Decode(eatingDolphin.bytes,2)==0x51 && eatingDolphin.bytes[6]==1);
  assert(eatingDolphin.bytes[8]==0x89 && eatingDolphin.bytes[9]==0xc7);
  GameX86 swimmingDolphin;
  swimmingDolphin.InitializeDolphinPose(false);
  assert(swimmingDolphin.calls.size()==1 && swimmingDolphin.calls[0].target==0x52c310);
  GameX86 chewFlash;
  chewFlash.EaxField(0xb8,25);
  assert(chewFlash.bytes[0]==0xc7 && chewFlash.bytes[1]==0x80 &&
         Decode(chewFlash.bytes,2)==0xb8 && Decode(chewFlash.bytes,6)==25);
  zombieDelete.RemoveZombie(0x01020304);
  assert(zombieDelete.bytes[0]==0xb9 && Decode(zombieDelete.bytes,1)==0x01020304 &&
         zombieDelete.calls[0].target==0x530510);
  GameX86 dayGloom;
  dayGloom.PutPlant(0x12345678,2,3,42,false,true);
  assert(dayGloom.calls.size()==2 && dayGloom.calls[0].target==0x40d120 &&
         dayGloom.calls[1].target==0x45e860);
  assert(dayGloom.bytes.at(30)==0x50 && Decode(dayGloom.bytes,32)==0 && dayGloom.bytes.back()==0x58);
  GameX86 asleepGloom;
  asleepGloom.PutPlant(0x12345678,2,3,42,true,true);
  assert(Decode(asleepGloom.bytes,32)==1);
  GameX86 nightGloom;
  nightGloom.PutPlant(0x12345678,2,3,42,false,false);
  GameX86 readyCob;
  readyCob.Byte(0x60);
  readyCob.PutPlant(0x12345678,0,0,47,false,true,false,0);
  // Constructor returns at byte 31; explicit ready state and zero countdown
  // are written before playing the loaded idle animation without blending.
  assert(readyCob.bytes.at(31)==0xc7 && readyCob.bytes.at(33)==0x3c);
  assert(Decode(readyCob.bytes,34)==37);
  assert(readyCob.bytes.at(40)==0x54 && Decode(readyCob.bytes,41)==0);
  assert(readyCob.calls.back().target==0x45fd90);
  GameX86 emptyCob;
  emptyCob.Byte(0x60);
  emptyCob.PutPlant(0x12345678,0,0,47,false,true,false,1);
  assert(Decode(emptyCob.bytes,34)==35 && Decode(emptyCob.bytes,41)==0);
  assert(emptyCob.calls.back().target==0x45fd90);
  assert(nightGloom.calls.size()==1);
  GameX86 terrain;
  terrain.StoreDword(0x12345678,3);
  assert(terrain.bytes.size()==10 && terrain.bytes[0]==0xc7 && terrain.bytes[1]==5 &&
         Decode(terrain.bytes,2)==0x12345678 && Decode(terrain.bytes,6)==3);

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
