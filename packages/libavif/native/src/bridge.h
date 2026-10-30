#ifndef LAVIF_BRIDGE_H
#define LAVIF_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

typedef struct LavifBridgeDecoder LavifBridgeDecoder;

typedef struct LavifBridgeInfo {
    uint32_t width;
    uint32_t height;
    uint32_t source_depth;
    uint8_t has_alpha;
    uint32_t image_count;
    int32_t repetition_count;
    uint64_t duration_in_timescales;
    uint64_t timescale;
    uint8_t is_sequence;
} LavifBridgeInfo;

typedef struct LavifBridgeFrameInfo {
    uint32_t index;
    uint64_t duration_in_timescales;
    uint64_t timescale;
} LavifBridgeFrameInfo;

LavifBridgeDecoder *lavif_bridge_decoder_create(
    const uint8_t *data,
    size_t length,
    uint32_t max_threads,
    uint32_t max_dimension,
    uint32_t max_pixels,
    uint32_t target_width,
    uint32_t target_height,
    uint8_t require_static,
    LavifBridgeInfo *info,
    int32_t *status,
    char *error,
    size_t error_capacity);

int32_t lavif_bridge_decoder_decode_rgba8(
    LavifBridgeDecoder *bridge,
    uint8_t *pixels,
    uint32_t row_bytes,
    LavifBridgeFrameInfo *frame_info,
    char *error,
    size_t error_capacity);

int32_t lavif_bridge_decoder_reset(
    LavifBridgeDecoder *bridge,
    char *error,
    size_t error_capacity);

void lavif_bridge_decoder_destroy(LavifBridgeDecoder *bridge);

const char *lavif_bridge_version(void);

void lavif_bridge_codec_versions(char *output, size_t capacity);

const char *lavif_bridge_features(void);

#endif
