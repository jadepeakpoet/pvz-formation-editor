#ifndef RUNNER_GAME_X86_H_
#define RUNNER_GAME_X86_H_
#include <cstddef>
#include <cstdint>
#include <cstring>
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
  void PlantField(uint8_t offset,uint32_t value) {
    Byte(0xc7); Byte(0x40); Byte(offset); Dword(value);
  }
  void PlayBody(uint32_t track) {
    // 1051 Plant::PlayBodyReanim: EAX=plant, ECX=blend time,
    // stack=(track, loop type, float rate), callee pops 12 bytes.
    Byte(0x50); Push(0x41400000); Push(0); Push(track);
    Byte(0x31); Byte(0xc9); Call(0x45fd90); Byte(0x58);
  }
  void SetVisualState(int type,int state,bool asleep) {
    if(type==47) {
      PlantField(0x3c,state==0 ? 37u : 35u);
      // Empty appearance means cooldown complete: begin charging next update.
      // A loaded appearance skips charging and is ready before the loop resumes.
      PlantField(0x54,0u);
      PlayBody(state==0 ? 0x6580d4u : 0x668cb0u);
    } else if(type==4) {
      PlantField(0x3c,state==0 ? 0u : 16u);
      PlantField(0x54,state==0 ? 1500u : 0u);
      PlayBody(state==0 ? 0x6580d4u : 0x657230u);
    } else if(type==9) {
      PlantField(0x3c,state==0 ? 23u : 25u);
      PlantField(0x54,state==0 ? 12000u : 0u);
      PlayBody(state==0 ? (asleep ? 0x668cd4u : 0x6580d4u)
                           : (asleep ? 0x668c80u : 0x668c90u));
    } else if(type==26) {
      PlantField(0x3c,state==0 ? 30u : 32u);
      PlayBody(state==0 ? 0x6580d4u : 0x668e78u);
    } else if(type==3 || type==23 || type==36 || type==46) {
      const uint32_t maximum=type==3 ? 4000u : type==23 ? 8000u : type==36 ? 400u : 450u;
      PlantField(0x40,state==0 ? maximum : state==1 ? maximum/2 : maximum/4);
    }
  }
  void PutPlant(uint32_t board,int row,int col,int type,bool asleep,bool daytime,bool imitater=false,int visualState=0) {
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
    SetVisualState(type,visualState,asleep);
  }
  void EaxField(uint32_t offset,uint32_t value) {
    Byte(0xc7); Byte(0x80); Dword(offset); Dword(value);
  }
  void EaxByte(uint32_t offset,uint8_t value) {
    Byte(0xc6); Byte(0x80); Dword(offset); Byte(value);
  }
  void RemoveZombie(uint32_t zombie) {
    Byte(0xb9); Dword(zombie); Call(0x530510);
  }
  void PutZombie(uint32_t board,int row,int type,float canvasX,
                 bool pool,int frameRow,int frameCol) {
    // 1051 Board::AddZombieInRow: EAX=board, EBX=from-wave, stack=type,row.
    Push(static_cast<uint32_t>(row)); Push(static_cast<uint32_t>(type));
    MovEax(board); Byte(0x31); Byte(0xdb); Call(0x40ddc0);
    const float x=canvasX-40.0f;
    uint32_t bits; std::memcpy(&bits,&x,sizeof(bits));
    EaxField(0x2c,bits); EaxField(8,static_cast<uint32_t>(static_cast<int>(x)));
    bool walking=false;
    if(type==14 && pool && (row==2 || row==3) && frameRow>0) {
      EaxField(0x28,frameCol==2 ? 55u : 53u);
      EaxByte(0xbd,1); EaxByte(0xbc,frameCol==2 ? 0 : 1);
      EaxField(0x64,0); EaxField(0x84,0); walking=true;
    } else if(type==11 && pool && (row==2 || row==3)) {
      EaxField(0x28,59); EaxByte(0xbd,1);
      EaxField(0x64,0); EaxField(0x84,0); walking=true;
    } else if(type==17) {
      EaxField(0x28,37); EaxField(0x64,0); EaxField(0x84,0); walking=true;
    }
    if(walking) {
      // StartWalkAnim takes blend time in ESI and returns with plain RET.
      Byte(0x50); Byte(0x31); Byte(0xf6); Call(0x52f2e0); Byte(0x58);
    }
  }
  void InitializeDolphinPose(bool eating) {
    if(eating) {
      EaxByte(0x51,1);
      // 1051 Zombie::PlayZombieReanim: EDI=this, callee pops four arguments.
      // Select the eating pose without blending from the constructor's walk.
      Byte(0x50); Byte(0x89); Byte(0xc7);
      Push(0); Push(0); Push(0); Push(0x66edd0);
      Call(0x528b00); Byte(0x58);
    }
    // 1051 Zombie::UpdateReanim takes EAX=this. This refreshes the pool offset
    // and attached head pose while the board remains paused.
    Byte(0x50); Call(0x52c310); Byte(0x58);
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
