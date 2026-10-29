// Adapted from cbreezy210/ACNH-Save-Editor (MIT). See Resources/Upstream-LICENSE.txt.
#include "SaveCrypto.h"
struct XorShift128 {
    uint32_t a, b, c, d;
    XorShift128(uint32_t seed) {
        uint32_t Mersenne = 0x6C078965;
        a = (Mersenne * (seed ^ (seed >> 30))) + 1;
        b = (Mersenne * (a   ^ (a   >> 30))) + 2;
        c = (Mersenne * (b   ^ (b   >> 30))) + 3;
        d = (Mersenne * (c   ^ (c   >> 30))) + 4;
    }
    uint32_t Next() { uint32_t t = a; a = b; b = c; c = d; t ^= t << 11; t ^= t >> 8; return d = t ^ d ^ (d >> 19); }
    uint64_t Next64() { const uint64_t high = Next(); const uint64_t low = Next(); return (high << 32) | low; }
};

void GetParam(const uint32_t* data, int index, uint8_t* result, int len) {
    uint32_t seed = data[data[index] & 0x7F];
    XorShift128 rand(seed);
    uint32_t prms = data[data[index + 1] & 0x7F] & 0x7F;
    int rndRollCount = (prms & 0xF) + 1;
    for (int i = 0; i < rndRollCount; i++) rand.Next64();
    for (int i = 0; i < len; i++) result[i] = (uint8_t)(rand.Next() >> 24);
}

static const uint8_t sbox[256] = {
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};
static const uint8_t rcon[11] = {0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36};
static uint8_t xtime(uint8_t x) { return (x << 1) ^ (((x >> 7) & 1) * 0x1b); }
static void KeyExpansion(const uint8_t* key, uint8_t* rk) {
    for (int i = 0; i < 16; i++) rk[i] = key[i];
    for (int i = 4; i < 44; i++) {
        uint8_t t[4];
        for (int j = 0; j < 4; j++) t[j] = rk[(i-1)*4+j];
        if (i % 4 == 0) { uint8_t q = t[0]; t[0] = sbox[t[1]] ^ rcon[i/4]; t[1] = sbox[t[2]]; t[2] = sbox[t[3]]; t[3] = sbox[q]; }
        for (int j = 0; j < 4; j++) rk[i*4+j] = rk[(i-4)*4+j] ^ t[j];
    }
}
static void AesEncryptBlock(const uint8_t* rk, const uint8_t* in, uint8_t* out) {
    uint8_t s[16];
    for (int i = 0; i < 16; i++) s[i] = in[i];
    for (int i = 0; i < 16; i++) s[i] ^= rk[i];
    for (int r = 1; r < 10; r++) {
        for (int i = 0; i < 16; i++) s[i] = sbox[s[i]];
        uint8_t t;
        t=s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
        t=s[2]; s[2]=s[10]; s[10]=t; t=s[6]; s[6]=s[14]; s[14]=t;
        t=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=s[3]; s[3]=t;
        for (int c = 0; c < 4; c++) {
            uint8_t a=s[c*4], b=s[c*4+1], d=s[c*4+2], e=s[c*4+3], x=a^b^d^e;
            s[c*4]   ^= x ^ xtime(a^b); s[c*4+1] ^= x ^ xtime(b^d);
            s[c*4+2] ^= x ^ xtime(d^e); s[c*4+3] ^= x ^ xtime(e^a);
        }
        for (int i = 0; i < 16; i++) s[i] ^= rk[r*16+i];
    }
    for (int i = 0; i < 16; i++) s[i] = sbox[s[i]];
    { uint8_t t; t=s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
      t=s[2]; s[2]=s[10]; s[10]=t; t=s[6]; s[6]=s[14]; s[14]=t;
      t=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=s[3]; s[3]=t; }
    for (int i = 0; i < 16; i++) out[i] = s[i] ^ rk[160+i];
}

void CryptACNH(const uint8_t* header, uint8_t* data, size_t dataLen) {
    uint32_t imp[128]; for (size_t i=0;i<128;i++) { const uint8_t* p=header+0x100+i*4; imp[i]=(uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24); }
    uint8_t key[16], ctr[16];
    GetParam(imp, 0, key, 16); GetParam(imp, 2, ctr, 16);
    uint8_t rk[176]; KeyExpansion(key, rk);
    uint8_t ek[16];
    for (size_t off = 0; off < dataLen; off += 16) {
        AesEncryptBlock(rk, ctr, ek);
        size_t bl = 16; if (off + bl > dataLen) bl = dataLen - off;
        for (size_t i = 0; i < bl; i++) data[off+i] ^= ek[i];
        for (int i = 15; i >= 0; i--) { if (++ctr[i] != 0) break; }
    }
}

static uint32_t Scramble(uint32_t v) { v = (v * 0x16A88000) | ((v * 0xCC9E2D51) >> 17); v *= 0x1B873593; return v; }
static uint32_t Advance(uint32_t c, uint32_t v) { c ^= Scramble(v); c = (c >> 19) | (c << 13); c = (c * 5) + 0xE6546B64; return c; }
static uint32_t Finalize(uint32_t c, uint32_t len) { c ^= len; c ^= c >> 16; c *= 0x85EBCA6B; c ^= c >> 13; c *= 0xC2B2AE35; c ^= c >> 16; return c; }
static uint32_t Murmur3Hash(const uint8_t* data, size_t len) {
    uint32_t c = 0; 
    for (size_t i = 0; i < len / 4; i++) c = Advance(c, (uint32_t)data[i*4] | ((uint32_t)data[i*4+1]<<8) | ((uint32_t)data[i*4+2]<<16) | ((uint32_t)data[i*4+3]<<24));
    return Finalize(c, (uint32_t)len);
}

extern "C" int acnh_crypt(const uint8_t* header, size_t headerLength, uint8_t* data, size_t length) { if (!header || headerLength != 0x300 || !data) return 0; CryptACNH(header, data, length); return 1; }
extern "C" uint32_t acnh_hash(const uint8_t* data, size_t length) { return Murmur3Hash(data, length); }
extern "C" void acnh_aes_block(const uint8_t* key, const uint8_t* input, uint8_t* output) { uint8_t rk[176]; KeyExpansion(key, rk); AesEncryptBlock(rk, input, output); }
