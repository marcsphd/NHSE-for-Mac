#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
int acnh_crypt(const uint8_t* header, size_t headerLength, uint8_t* data, size_t length);
uint32_t acnh_hash(const uint8_t* data, size_t length);
void acnh_aes_block(const uint8_t* key, const uint8_t* input, uint8_t* output);
#ifdef __cplusplus
}
#endif
