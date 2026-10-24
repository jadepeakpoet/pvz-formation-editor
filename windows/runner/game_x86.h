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
  void StoreDword(uint32_t address,uint32_t value) {
    Byte(0xc7); Byte(0x05); Dword(address); Dword(value);
  }
  static bool Sleepable(int type) {
    return type==8 || type==9 || type==10 || type==12 || type==13 || type==14 ||
           type==15 || type==24 || type==31 || type==42;
  }
  void PutPlant(uint32_t board,int row,int col,int type,bool asleep,bool daytime,bool imitater=false) {
    Push(imitater ? static_cast<uint32_t>(type) : 0xffffffff);
    Push(imitater ? 48u : static_cast<uint32_t>(type));
    MovEax(static_cast<uint32_t>(row)); Push(static_cast<uint32_t>(col)); Push(board); Call(0x40d120);
    if(imitater) {
      // Transform the imitater, retaining the converted plant's data-array slot.
      Byte(0x8b); Byte(0x0d); Dword(board+0xac);
      Byte(0x8b); Byte(0x1d); Dword(board+0xb8);
      Byte(0x69); Byte(0xdb); Dword(0x14c);
      Byte(0x01); Byte(0xd9); Byte(0x51);
      Byte(0x89); Byte(0xc6); Call(0x466b80); Byte(0x58);
    }
    if(Sleepable(type) && (daytime || asleep)) {
      Byte(0x50); Push(asleep ? 1u : 0u); Call(0x45e860); Byte(0x58);
    }
    if(type==4 || type==9) { Byte(0xc7); Byte(0x40); Byte(0x54); Dword(1); }
  }
  void PutRake(uint32_t board,int row,int col) {
    // Enter the original constructor after random row selection and inventory
    // consumption. Recreate its stack frame so its ordinary epilogue is valid.
    GameX86 frame;
    frame.Byte(0x55); frame.Byte(0x8b); frame.Byte(0xec);
    frame.Byte(0x83); frame.Byte(0xe4); frame.Byte(0xf8);
    frame.Byte(0x83); frame.Byte(0xec); frame.Byte(0x44);
    frame.Byte(0x53); frame.Byte(0x8b); frame.Byte(0x5d); frame.Byte(0x08);
    frame.Byte(0x56); frame.Byte(0x57);
    frame.Byte(0xba); frame.Dword(static_cast<uint32_t>(row));
    frame.Byte(0xc7); frame.Byte(0x44); frame.Byte(0x24); frame.Byte(0x10);
    frame.Dword(static_cast<uint32_t>(col));
    frame.MovEax(0x40bb2c); frame.Byte(0xff); frame.Byte(0xe0);
    Push(board);
    Byte(0xe8); Dword(5); // Call over the following jump into the local frame.
    Byte(0xe9); Dword(static_cast<uint32_t>(frame.bytes.size()));
    bytes.insert(bytes.end(),frame.bytes.begin(),frame.bytes.end());
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
