#include <webp/encode.h>

extern "C" __declspec(dllexport) size_t PvzWebPEncodeRGBA(
    const uint8_t* rgba, int width, int height, int stride, float quality,
    uint8_t** output) {
  return WebPEncodeRGBA(rgba, width, height, stride, quality, output);
}

extern "C" __declspec(dllexport) void PvzWebPFree(void* output) {
  WebPFree(output);
}
