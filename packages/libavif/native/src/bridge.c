#include "bridge.h"

#include <avif/avif.h>
#include <libyuv/version.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LAVIF_STRINGIFY_INNER(value) #value
#define LAVIF_STRINGIFY(value) LAVIF_STRINGIFY_INNER(value)

struct LavifBridgeDecoder {
    avifDecoder *decoder;
    uint32_t target_width;
    uint32_t target_height;
};

enum {
    LAVIF_OK = 0,
    LAVIF_INVALID_INPUT = 1,
    LAVIF_DECODE_FAILED = 2,
    LAVIF_LIMIT_EXCEEDED = 3,
    LAVIF_UNSUPPORTED = 4,
    LAVIF_OUT_OF_MEMORY = 5,
    LAVIF_INTERNAL = 6,
    LAVIF_END_OF_SEQUENCE = 7
};

static void lavif_copy_error(
    char *output,
    size_t capacity,
    const char *message,
    const avifDiagnostics *diagnostics) {
    if (output == NULL || capacity == 0) {
        return;
    }
    if (diagnostics != NULL && diagnostics->error[0] != '\0') {
        (void)snprintf(output, capacity, "%s: %s", message, diagnostics->error);
    } else {
        (void)snprintf(output, capacity, "%s", message);
    }
}

static int32_t lavif_status_for_result(avifResult result) {
    switch (result) {
        case AVIF_RESULT_INVALID_FTYP:
        case AVIF_RESULT_NO_CONTENT:
        case AVIF_RESULT_BMFF_PARSE_FAILED:
        case AVIF_RESULT_TRUNCATED_DATA:
        case AVIF_RESULT_INVALID_ARGUMENT:
            return LAVIF_INVALID_INPUT;
        case AVIF_RESULT_OUT_OF_MEMORY:
            return LAVIF_OUT_OF_MEMORY;
        case AVIF_RESULT_NOT_IMPLEMENTED:
        case AVIF_RESULT_UNSUPPORTED_DEPTH:
            return LAVIF_UNSUPPORTED;
        case AVIF_RESULT_INTERNAL_ERROR:
            return LAVIF_INTERNAL;
        default:
            return LAVIF_DECODE_FAILED;
    }
}

static int32_t lavif_fail_result(
    avifResult result,
    const avifDiagnostics *diagnostics,
    char *error,
    size_t error_capacity) {
    lavif_copy_error(error, error_capacity, avifResultToString(result), diagnostics);
    return lavif_status_for_result(result);
}

static avifBool lavif_has_unsupported_transform(const avifImage *image) {
    avifTransformFlags flags = image->transformFlags;
    if ((flags & AVIF_TRANSFORM_PASP) != 0 &&
        image->pasp.hSpacing != 0 &&
        image->pasp.hSpacing == image->pasp.vSpacing) {
        flags &= ~AVIF_TRANSFORM_PASP;
    }
    return flags != AVIF_TRANSFORM_NONE;
}

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
    size_t error_capacity) {
    if (status == NULL) {
        return NULL;
    }
    *status = LAVIF_INVALID_INPUT;
    if (data == NULL || length == 0 || info == NULL || max_threads == 0 ||
        max_dimension == 0 || max_pixels == 0) {
        lavif_copy_error(error, error_capacity, "Invalid AVIF decode arguments", NULL);
        return NULL;
    }

    LavifBridgeDecoder *bridge = (LavifBridgeDecoder *)calloc(1, sizeof(*bridge));
    if (bridge == NULL) {
        *status = LAVIF_OUT_OF_MEMORY;
        lavif_copy_error(error, error_capacity, "Could not allocate the AVIF decoder", NULL);
        return NULL;
    }

    bridge->decoder = avifDecoderCreate();
    if (bridge->decoder == NULL) {
        free(bridge);
        *status = LAVIF_OUT_OF_MEMORY;
        lavif_copy_error(error, error_capacity, "Could not create the AVIF decoder", NULL);
        return NULL;
    }
    bridge->decoder->maxThreads = (int)max_threads;
    bridge->decoder->imageDimensionLimit = max_dimension;
    bridge->decoder->imageSizeLimit = max_pixels;
    bridge->decoder->imageCountLimit = AVIF_DEFAULT_IMAGE_COUNT_LIMIT;

    avifResult result = avifDecoderSetIOMemory(bridge->decoder, data, length);
    if (result == AVIF_RESULT_OK) {
        result = avifDecoderParse(bridge->decoder);
    }
    if (result != AVIF_RESULT_OK) {
        *status = lavif_fail_result(
            result, &bridge->decoder->diag, error, error_capacity);
        lavif_bridge_decoder_destroy(bridge);
        return NULL;
    }

    if (require_static && bridge->decoder->imageSequenceTrackPresent) {
        *status = LAVIF_UNSUPPORTED;
        lavif_copy_error(
            error,
            error_capacity,
            "Animated AVIF sequences are not supported by the static decoder",
            NULL);
        lavif_bridge_decoder_destroy(bridge);
        return NULL;
    }
    if (lavif_has_unsupported_transform(bridge->decoder->image)) {
        *status = LAVIF_UNSUPPORTED;
        lavif_copy_error(
            error,
            error_capacity,
            "AVIF clean-aperture, rotation, mirror, and pixel-aspect transforms are not supported",
            NULL);
        lavif_bridge_decoder_destroy(bridge);
        return NULL;
    }

    const uint32_t source_width = bridge->decoder->image->width;
    const uint32_t source_height = bridge->decoder->image->height;
    if (bridge->decoder->imageCount <= 0) {
        *status = LAVIF_INVALID_INPUT;
        lavif_copy_error(error, error_capacity, "AVIF contains no decodable images", NULL);
        lavif_bridge_decoder_destroy(bridge);
        return NULL;
    }
    info->source_depth = bridge->decoder->image->depth;
    info->has_alpha = bridge->decoder->alphaPresent ? 1 : 0;
    info->image_count = (uint32_t)bridge->decoder->imageCount;
    info->repetition_count = bridge->decoder->repetitionCount;
    info->duration_in_timescales = bridge->decoder->durationInTimescales;
    info->timescale = bridge->decoder->timescale;
    info->is_sequence = bridge->decoder->imageSequenceTrackPresent ? 1 : 0;
    if (source_width == 0 || source_height == 0 ||
        source_width > max_dimension || source_height > max_dimension ||
        (uint64_t)source_width * (uint64_t)source_height > max_pixels) {
        *status = LAVIF_LIMIT_EXCEEDED;
        lavif_copy_error(error, error_capacity, "AVIF dimensions exceed the configured limits", NULL);
        lavif_bridge_decoder_destroy(bridge);
        return NULL;
    }

    if (target_width == 0 && target_height == 0) {
        target_width = source_width;
        target_height = source_height;
    } else if (target_width == 0) {
        const uint64_t scaled =
            ((uint64_t)target_height * source_width + (source_height / 2)) /
            source_height;
        target_width = (uint32_t)((scaled == 0) ? 1 : scaled);
    } else if (target_height == 0) {
        const uint64_t scaled =
            ((uint64_t)target_width * source_height) / source_width;
        target_height = (uint32_t)((scaled == 0) ? 1 : scaled);
    }
    if (target_width > max_dimension || target_height > max_dimension ||
        (uint64_t)target_width * (uint64_t)target_height > max_pixels) {
        *status = LAVIF_LIMIT_EXCEEDED;
        lavif_copy_error(error, error_capacity, "AVIF target dimensions exceed the configured limits", NULL);
        lavif_bridge_decoder_destroy(bridge);
        return NULL;
    }

    bridge->target_width = target_width;
    bridge->target_height = target_height;
    info->width = target_width;
    info->height = target_height;

    *status = LAVIF_OK;
    return bridge;
}

int32_t lavif_bridge_decoder_decode_rgba8(
    LavifBridgeDecoder *bridge,
    uint8_t *pixels,
    uint32_t row_bytes,
    LavifBridgeFrameInfo *frame_info,
    char *error,
    size_t error_capacity) {
    if (bridge == NULL || bridge->decoder == NULL || pixels == NULL || frame_info == NULL) {
        lavif_copy_error(error, error_capacity, "Invalid AVIF decoder state", NULL);
        return LAVIF_INTERNAL;
    }

    avifResult result = avifDecoderNextImage(bridge->decoder);
    if (result == AVIF_RESULT_NO_IMAGES_REMAINING) {
        return LAVIF_END_OF_SEQUENCE;
    }
    if (result != AVIF_RESULT_OK) {
        return lavif_fail_result(
            result, &bridge->decoder->diag, error, error_capacity);
    }
    if (lavif_has_unsupported_transform(bridge->decoder->image)) {
        lavif_copy_error(
            error,
            error_capacity,
            "AVIF frame contains unsupported render transforms",
            NULL);
        return LAVIF_UNSUPPORTED;
    }

    result = avifImageScale(
        bridge->decoder->image,
        bridge->target_width,
        bridge->target_height,
        &bridge->decoder->diag);
    if (result != AVIF_RESULT_OK) {
        return lavif_fail_result(
            result, &bridge->decoder->diag, error, error_capacity);
    }

    avifRGBImage rgb;
    avifRGBImageSetDefaults(&rgb, bridge->decoder->image);
    rgb.format = AVIF_RGB_FORMAT_RGBA;
    rgb.depth = 8;
    rgb.alphaPremultiplied = AVIF_TRUE;
    rgb.maxThreads = bridge->decoder->maxThreads;
    rgb.pixels = pixels;
    rgb.rowBytes = row_bytes;

    result = avifImageYUVToRGB(bridge->decoder->image, &rgb);
    if (result != AVIF_RESULT_OK) {
        return lavif_fail_result(
            result, &bridge->decoder->diag, error, error_capacity);
    }
    frame_info->index = (uint32_t)bridge->decoder->imageIndex;
    frame_info->duration_in_timescales =
        bridge->decoder->imageTiming.durationInTimescales;
    frame_info->timescale = bridge->decoder->imageTiming.timescale;
    return LAVIF_OK;
}

int32_t lavif_bridge_decoder_reset(
    LavifBridgeDecoder *bridge,
    char *error,
    size_t error_capacity) {
    if (bridge == NULL || bridge->decoder == NULL) {
        lavif_copy_error(error, error_capacity, "Invalid AVIF decoder state", NULL);
        return LAVIF_INTERNAL;
    }
    const avifResult result = avifDecoderReset(bridge->decoder);
    if (result != AVIF_RESULT_OK) {
        return lavif_fail_result(
            result, &bridge->decoder->diag, error, error_capacity);
    }
    return LAVIF_OK;
}

void lavif_bridge_decoder_destroy(LavifBridgeDecoder *bridge) {
    if (bridge == NULL) {
        return;
    }
    avifDecoderDestroy(bridge->decoder);
    free(bridge);
}

const char *lavif_bridge_version(void) {
    return avifVersion();
}

void lavif_bridge_codec_versions(char *output, size_t capacity) {
    if (output == NULL || capacity == 0) {
        return;
    }
    char versions[256] = {0};
    avifCodecVersions(versions);
    (void)snprintf(output, capacity, "%s", versions);
}

const char *lavif_bridge_features(void) {
    return "libyuv:" LAVIF_STRINGIFY(LIBYUV_VERSION);
}
