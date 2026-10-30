use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr::{self, NonNull};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;

const ABI_VERSION: u32 = 6;
const ERROR_CAPACITY: usize = 512;
const LAVIF_OK: i32 = 0;
const LAVIF_INVALID_INPUT: i32 = 1;
const LAVIF_LIMIT_EXCEEDED: i32 = 3;
const LAVIF_OUT_OF_MEMORY: i32 = 5;
const LAVIF_INTERNAL: i32 = 6;
const LAVIF_END_OF_SEQUENCE: i32 = 7;

#[repr(C)]
#[derive(Clone, Copy)]
struct LavifBridgeInfo {
    width: u32,
    height: u32,
    source_depth: u32,
    has_alpha: u8,
    image_count: u32,
    repetition_count: i32,
    duration_in_timescales: u64,
    timescale: u64,
    is_sequence: u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct LavifBridgeFrameInfo {
    index: u32,
    duration_in_timescales: u64,
    timescale: u64,
}

enum LavifBridgeDecoder {}

unsafe extern "C" {
    fn lavif_bridge_decoder_create(
        data: *const u8,
        length: usize,
        max_threads: u32,
        max_dimension: u32,
        max_pixels: u32,
        target_width: u32,
        target_height: u32,
        require_static: u8,
        info: *mut LavifBridgeInfo,
        status: *mut i32,
        error: *mut c_char,
        error_capacity: usize,
    ) -> *mut LavifBridgeDecoder;
    fn lavif_bridge_decoder_decode_rgba8(
        decoder: *mut LavifBridgeDecoder,
        pixels: *mut u8,
        row_bytes: u32,
        frame_info: *mut LavifBridgeFrameInfo,
        error: *mut c_char,
        error_capacity: usize,
    ) -> i32;
    fn lavif_bridge_decoder_reset(
        decoder: *mut LavifBridgeDecoder,
        error: *mut c_char,
        error_capacity: usize,
    ) -> i32;
    fn lavif_bridge_decoder_destroy(decoder: *mut LavifBridgeDecoder);
    fn lavif_bridge_version() -> *const c_char;
    fn lavif_bridge_codec_versions(output: *mut c_char, capacity: usize);
    fn lavif_bridge_features() -> *const c_char;
}

#[repr(C)]
pub struct LavifDecodeResult {
    request_id: u64,
    status: i32,
    pixels: *mut u8,
    pixels_length: usize,
    pixels_owner: *mut c_void,
    width: u32,
    height: u32,
    row_bytes: u32,
    source_bit_depth: u32,
    has_alpha: u8,
    error: *mut u8,
    error_length: usize,
}

impl LavifDecodeResult {
    fn failure(request_id: u64, status: i32, message: impl Into<Vec<u8>>) -> Self {
        let (error, error_length) = leak_bytes(message.into());
        Self {
            request_id,
            status,
            pixels: ptr::null_mut(),
            pixels_length: 0,
            pixels_owner: ptr::null_mut(),
            width: 0,
            height: 0,
            row_bytes: 0,
            source_bit_depth: 0,
            has_alpha: 0,
            error,
            error_length,
        }
    }
}

#[repr(C)]
pub struct LavifSequenceResult {
    request_id: u64,
    status: i32,
    handle: u64,
    pixels: *mut u8,
    pixels_length: usize,
    pixels_owner: *mut c_void,
    width: u32,
    height: u32,
    row_bytes: u32,
    source_bit_depth: u32,
    has_alpha: u8,
    frame_count: u32,
    repetition_count: i32,
    duration_in_timescales: u64,
    timescale: u64,
    frame_index: u32,
    frame_duration_in_timescales: u64,
    frame_timescale: u64,
    error: *mut u8,
    error_length: usize,
}

impl LavifSequenceResult {
    fn empty(request_id: u64, status: i32) -> Self {
        Self {
            request_id,
            status,
            handle: 0,
            pixels: ptr::null_mut(),
            pixels_length: 0,
            pixels_owner: ptr::null_mut(),
            width: 0,
            height: 0,
            row_bytes: 0,
            source_bit_depth: 0,
            has_alpha: 0,
            frame_count: 0,
            repetition_count: 0,
            duration_in_timescales: 0,
            timescale: 0,
            frame_index: 0,
            frame_duration_in_timescales: 0,
            frame_timescale: 0,
            error: ptr::null_mut(),
            error_length: 0,
        }
    }

    fn failure(request_id: u64, status: i32, message: impl Into<Vec<u8>>) -> Self {
        let mut result = Self::empty(request_id, status);
        (result.error, result.error_length) = leak_bytes(message.into());
        result
    }
}

struct SequenceState {
    _input: Box<[u8]>,
    decoder: DecoderGuard,
    info: LavifBridgeInfo,
}

type SharedSequence = Arc<Mutex<SequenceState>>;

static SEQUENCES: OnceLock<Mutex<HashMap<u64, SharedSequence>>> = OnceLock::new();
static NEXT_SEQUENCE_HANDLE: AtomicU64 = AtomicU64::new(1);

fn sequences() -> &'static Mutex<HashMap<u64, SharedSequence>> {
    SEQUENCES.get_or_init(|| Mutex::new(HashMap::new()))
}

struct DecoderGuard(NonNull<LavifBridgeDecoder>);

unsafe impl Send for DecoderGuard {}

impl Drop for DecoderGuard {
    fn drop(&mut self) {
        unsafe { lavif_bridge_decoder_destroy(self.0.as_ptr()) };
    }
}

#[no_mangle]
pub extern "C" fn lavif_decode_rgba8(
    data: *const u8,
    length: usize,
    max_threads: u32,
    max_dimension: u32,
    max_pixels: u32,
    target_width: u32,
    target_height: u32,
) -> *mut LavifDecodeResult {
    let result = catch_unwind(AssertUnwindSafe(|| {
        decode(
            0,
            data,
            length,
            max_threads,
            max_dimension,
            max_pixels,
            target_width,
            target_height,
        )
    }))
    .unwrap_or_else(|_| {
        LavifDecodeResult::failure(0, LAVIF_INTERNAL, b"Native AVIF decoder panicked".to_vec())
    });
    Box::into_raw(Box::new(result))
}

fn decode(
    request_id: u64,
    data: *const u8,
    length: usize,
    max_threads: u32,
    max_dimension: u32,
    max_pixels: u32,
    target_width: u32,
    target_height: u32,
) -> LavifDecodeResult {
    if data.is_null() || length == 0 {
        return LavifDecodeResult::failure(request_id, 1, b"AVIF input is empty".to_vec());
    }

    let mut info = LavifBridgeInfo {
        width: 0,
        height: 0,
        source_depth: 0,
        has_alpha: 0,
        image_count: 0,
        repetition_count: 0,
        duration_in_timescales: 0,
        timescale: 0,
        is_sequence: 0,
    };
    let mut status = LAVIF_OK;
    let mut error = [0 as c_char; ERROR_CAPACITY];
    let decoder = unsafe {
        lavif_bridge_decoder_create(
            data,
            length,
            max_threads,
            max_dimension,
            max_pixels,
            target_width,
            target_height,
            1,
            &mut info,
            &mut status,
            error.as_mut_ptr(),
            error.len(),
        )
    };
    let Some(decoder) = NonNull::new(decoder) else {
        return LavifDecodeResult::failure(request_id, status, error_message(&error));
    };
    let decoder = DecoderGuard(decoder);

    let Some(row_bytes) = info.width.checked_mul(4) else {
        return LavifDecodeResult::failure(
            request_id,
            LAVIF_LIMIT_EXCEEDED,
            b"AVIF row size exceeds the supported limit".to_vec(),
        );
    };
    let Some(pixels_length_u32) = row_bytes.checked_mul(info.height) else {
        return LavifDecodeResult::failure(
            request_id,
            LAVIF_LIMIT_EXCEEDED,
            b"AVIF pixel buffer exceeds the supported limit".to_vec(),
        );
    };
    let pixels_length = pixels_length_u32 as usize;
    let mut pixels = Vec::new();
    if pixels.try_reserve_exact(pixels_length).is_err() {
        return LavifDecodeResult::failure(
            request_id,
            LAVIF_OUT_OF_MEMORY,
            b"Could not allocate the AVIF pixel buffer".to_vec(),
        );
    }
    pixels.resize(pixels_length, 0);

    let mut frame_info = LavifBridgeFrameInfo {
        index: 0,
        duration_in_timescales: 0,
        timescale: 0,
    };
    error.fill(0);
    status = unsafe {
        lavif_bridge_decoder_decode_rgba8(
            decoder.0.as_ptr(),
            pixels.as_mut_ptr(),
            row_bytes,
            &mut frame_info,
            error.as_mut_ptr(),
            error.len(),
        )
    };
    if status != LAVIF_OK {
        return LavifDecodeResult::failure(request_id, status, error_message(&error));
    }

    let (pixels, pixels_length, pixels_owner) = own_pixels(pixels);
    LavifDecodeResult {
        request_id,
        status,
        pixels,
        pixels_length,
        pixels_owner,
        width: info.width,
        height: info.height,
        row_bytes,
        source_bit_depth: info.source_depth,
        has_alpha: info.has_alpha,
        error: ptr::null_mut(),
        error_length: 0,
    }
}

fn open_sequence(
    request_id: u64,
    input: Box<[u8]>,
    max_threads: u32,
    max_dimension: u32,
    max_pixels: u32,
    target_width: u32,
    target_height: u32,
    prefetch_first_frame: bool,
) -> LavifSequenceResult {
    let mut info = LavifBridgeInfo {
        width: 0,
        height: 0,
        source_depth: 0,
        has_alpha: 0,
        image_count: 0,
        repetition_count: 0,
        duration_in_timescales: 0,
        timescale: 0,
        is_sequence: 0,
    };
    let mut status = LAVIF_OK;
    let mut error = [0 as c_char; ERROR_CAPACITY];
    let decoder = unsafe {
        lavif_bridge_decoder_create(
            input.as_ptr(),
            input.len(),
            max_threads,
            max_dimension,
            max_pixels,
            target_width,
            target_height,
            0,
            &mut info,
            &mut status,
            error.as_mut_ptr(),
            error.len(),
        )
    };
    let Some(decoder) = NonNull::new(decoder) else {
        return LavifSequenceResult::failure(request_id, status, error_message(&error));
    };
    if info.image_count == 0 {
        unsafe { lavif_bridge_decoder_destroy(decoder.as_ptr()) };
        return LavifSequenceResult::failure(
            request_id,
            LAVIF_INVALID_INPUT,
            b"AVIF sequence contains no frames".to_vec(),
        );
    }

    let Some(row_bytes) = info.width.checked_mul(4) else {
        unsafe { lavif_bridge_decoder_destroy(decoder.as_ptr()) };
        return LavifSequenceResult::failure(
            request_id,
            LAVIF_LIMIT_EXCEEDED,
            b"AVIF row size exceeds the supported limit".to_vec(),
        );
    };
    let state = Arc::new(Mutex::new(SequenceState {
        _input: input,
        decoder: DecoderGuard(decoder),
        info,
    }));
    let handle = NEXT_SEQUENCE_HANDLE.fetch_add(1, Ordering::Relaxed);
    if handle == 0 {
        return LavifSequenceResult::failure(
            request_id,
            LAVIF_INTERNAL,
            b"AVIF sequence handle space was exhausted".to_vec(),
        );
    }
    let mut registry = match sequences().lock() {
        Ok(registry) => registry,
        Err(_) => {
            return LavifSequenceResult::failure(
                request_id,
                LAVIF_INTERNAL,
                b"AVIF sequence registry is unavailable".to_vec(),
            )
        }
    };
    registry.insert(handle, Arc::clone(&state));
    drop(registry);
    if prefetch_first_frame {
        let mut result = sequence_next(request_id, state);
        if result.status != LAVIF_OK {
            if let Ok(mut registry) = sequences().lock() {
                registry.remove(&handle);
            }
            return result;
        }
        result.handle = handle;
        return result;
    }
    let mut result = LavifSequenceResult::empty(request_id, LAVIF_OK);
    result.handle = handle;
    result.width = info.width;
    result.height = info.height;
    result.row_bytes = row_bytes;
    result.source_bit_depth = info.source_depth;
    result.has_alpha = info.has_alpha;
    result.frame_count = info.image_count;
    result.repetition_count = info.repetition_count;
    result.duration_in_timescales = info.duration_in_timescales;
    result.timescale = info.timescale;
    result
}

fn sequence_next(request_id: u64, sequence: SharedSequence) -> LavifSequenceResult {
    let mut state = match sequence.lock() {
        Ok(state) => state,
        Err(_) => {
            return LavifSequenceResult::failure(
                request_id,
                LAVIF_INTERNAL,
                b"AVIF sequence decoder is unavailable".to_vec(),
            )
        }
    };
    let Some(row_bytes) = state.info.width.checked_mul(4) else {
        return LavifSequenceResult::failure(
            request_id,
            LAVIF_LIMIT_EXCEEDED,
            b"AVIF row size exceeds the supported limit".to_vec(),
        );
    };
    let Some(pixels_length_u32) = row_bytes.checked_mul(state.info.height) else {
        return LavifSequenceResult::failure(
            request_id,
            LAVIF_LIMIT_EXCEEDED,
            b"AVIF pixel buffer exceeds the supported limit".to_vec(),
        );
    };
    let pixels_length = pixels_length_u32 as usize;
    let mut pixels = Vec::new();
    if pixels.try_reserve_exact(pixels_length).is_err() {
        return LavifSequenceResult::failure(
            request_id,
            LAVIF_OUT_OF_MEMORY,
            b"Could not allocate the AVIF sequence frame buffer".to_vec(),
        );
    }
    pixels.resize(pixels_length, 0);
    let mut frame_info = LavifBridgeFrameInfo {
        index: 0,
        duration_in_timescales: 0,
        timescale: 0,
    };
    let mut error = [0 as c_char; ERROR_CAPACITY];
    let status = unsafe {
        lavif_bridge_decoder_decode_rgba8(
            state.decoder.0.as_ptr(),
            pixels.as_mut_ptr(),
            row_bytes,
            &mut frame_info,
            error.as_mut_ptr(),
            error.len(),
        )
    };
    if status == LAVIF_END_OF_SEQUENCE {
        return LavifSequenceResult::empty(request_id, status);
    }
    if status != LAVIF_OK {
        return LavifSequenceResult::failure(request_id, status, error_message(&error));
    }
    if state.info.image_count > 1
        && (frame_info.timescale == 0 || frame_info.duration_in_timescales == 0)
    {
        return LavifSequenceResult::failure(
            request_id,
            LAVIF_INVALID_INPUT,
            b"Animated AVIF frame has no positive duration".to_vec(),
        );
    }

    let (pixels, pixels_length, pixels_owner) = own_pixels(pixels);
    let mut result = LavifSequenceResult::empty(request_id, LAVIF_OK);
    result.pixels = pixels;
    result.pixels_length = pixels_length;
    result.pixels_owner = pixels_owner;
    result.width = state.info.width;
    result.height = state.info.height;
    result.row_bytes = row_bytes;
    result.source_bit_depth = state.info.source_depth;
    result.has_alpha = state.info.has_alpha;
    result.frame_count = state.info.image_count;
    result.repetition_count = state.info.repetition_count;
    result.duration_in_timescales = state.info.duration_in_timescales;
    result.timescale = state.info.timescale;
    result.frame_index = frame_info.index;
    result.frame_duration_in_timescales = frame_info.duration_in_timescales;
    result.frame_timescale = frame_info.timescale;
    result
}

fn sequence_reset(request_id: u64, sequence: SharedSequence) -> LavifSequenceResult {
    let state = match sequence.lock() {
        Ok(state) => state,
        Err(_) => {
            return LavifSequenceResult::failure(
                request_id,
                LAVIF_INTERNAL,
                b"AVIF sequence decoder is unavailable".to_vec(),
            )
        }
    };
    let mut error = [0 as c_char; ERROR_CAPACITY];
    let status = unsafe {
        lavif_bridge_decoder_reset(state.decoder.0.as_ptr(), error.as_mut_ptr(), error.len())
    };
    if status != LAVIF_OK {
        return LavifSequenceResult::failure(request_id, status, error_message(&error));
    }
    LavifSequenceResult::empty(request_id, LAVIF_OK)
}

type PostCObject = unsafe extern "C" fn(i64, *mut DartCObject) -> bool;

#[repr(C)]
union DartCObjectValue {
    as_int64: i64,
    alignment: [u64; 5],
}

#[repr(C)]
struct DartCObject {
    type_: i32,
    value: DartCObjectValue,
}

struct DecodeJob {
    request_id: u64,
    input: Box<[u8]>,
    max_threads: u32,
    max_dimension: u32,
    max_pixels: u32,
    target_width: u32,
    target_height: u32,
    port: i64,
    post_c_object: PostCObject,
}

struct SequenceOpenJob {
    request_id: u64,
    input: Box<[u8]>,
    max_threads: u32,
    max_dimension: u32,
    max_pixels: u32,
    target_width: u32,
    target_height: u32,
    prefetch_first_frame: bool,
    port: i64,
    post_c_object: PostCObject,
}

struct SequenceCommandJob {
    request_id: u64,
    sequence: SharedSequence,
    port: i64,
    post_c_object: PostCObject,
}

enum WorkerJob {
    Decode(DecodeJob),
    SequenceOpen(SequenceOpenJob),
    SequenceNext(SequenceCommandJob),
    SequenceReset(SequenceCommandJob),
}

struct DecodePool {
    sender: mpsc::Sender<WorkerJob>,
    worker_count: u32,
    threads_per_worker: u32,
}

static DECODE_POOL: OnceLock<Result<DecodePool, String>> = OnceLock::new();

fn decode_pool() -> Result<&'static DecodePool, &'static str> {
    DECODE_POOL
        .get_or_init(create_decode_pool)
        .as_ref()
        .map_err(String::as_str)
}

fn create_decode_pool() -> Result<DecodePool, String> {
    let processors = thread::available_parallelism()
        .map(|count| count.get())
        .unwrap_or(1);
    let mobile = cfg!(any(target_os = "android", target_os = "ios"));
    let worker_count = if mobile {
        1
    } else {
        processors.div_ceil(4).clamp(1, 4)
    };
    // Async decoding runs beside an application event loop and renderer. Keep
    // half of the reported CPU capacity available instead of letting codec
    // workers starve frame production during bursty image loading.
    let threads_per_worker = if mobile {
        processors.min(2)
    } else {
        (processors / (worker_count * 2)).max(1)
    } as u32;
    let (sender, receiver) = mpsc::channel::<WorkerJob>();
    let receiver = Arc::new(Mutex::new(receiver));

    for index in 0..worker_count {
        let receiver = Arc::clone(&receiver);
        thread::Builder::new()
            .name(format!("libavif-decode-{index}"))
            .spawn(move || decode_worker(receiver, threads_per_worker))
            .map_err(|error| format!("Could not start native AVIF decode worker: {error}"))?;
    }

    Ok(DecodePool {
        sender,
        worker_count: worker_count as u32,
        threads_per_worker,
    })
}

fn decode_worker(receiver: Arc<Mutex<mpsc::Receiver<WorkerJob>>>, threads_per_worker: u32) {
    loop {
        let job = {
            let receiver = match receiver.lock() {
                Ok(receiver) => receiver,
                Err(_) => return,
            };
            match receiver.recv() {
                Ok(job) => job,
                Err(_) => return,
            }
        };
        match job {
            WorkerJob::Decode(job) => {
                let result = catch_unwind(AssertUnwindSafe(|| {
                    decode(
                        job.request_id,
                        job.input.as_ptr(),
                        job.input.len(),
                        job.max_threads.min(threads_per_worker),
                        job.max_dimension,
                        job.max_pixels,
                        job.target_width,
                        job.target_height,
                    )
                }))
                .unwrap_or_else(|_| {
                    LavifDecodeResult::failure(
                        job.request_id,
                        LAVIF_INTERNAL,
                        b"Native AVIF decoder panicked".to_vec(),
                    )
                });
                post_decode_result(job.port, job.post_c_object, result);
            }
            WorkerJob::SequenceOpen(job) => {
                let result = catch_unwind(AssertUnwindSafe(|| {
                    open_sequence(
                        job.request_id,
                        job.input,
                        job.max_threads.min(threads_per_worker),
                        job.max_dimension,
                        job.max_pixels,
                        job.target_width,
                        job.target_height,
                        job.prefetch_first_frame,
                    )
                }))
                .unwrap_or_else(|_| {
                    LavifSequenceResult::failure(
                        job.request_id,
                        LAVIF_INTERNAL,
                        b"Native AVIF sequence decoder panicked".to_vec(),
                    )
                });
                post_sequence_result(job.port, job.post_c_object, result);
            }
            WorkerJob::SequenceNext(job) => {
                let result = catch_unwind(AssertUnwindSafe(|| {
                    sequence_next(job.request_id, job.sequence)
                }))
                .unwrap_or_else(|_| {
                    LavifSequenceResult::failure(
                        job.request_id,
                        LAVIF_INTERNAL,
                        b"Native AVIF sequence decoder panicked".to_vec(),
                    )
                });
                post_sequence_result(job.port, job.post_c_object, result);
            }
            WorkerJob::SequenceReset(job) => {
                let result = catch_unwind(AssertUnwindSafe(|| {
                    sequence_reset(job.request_id, job.sequence)
                }))
                .unwrap_or_else(|_| {
                    LavifSequenceResult::failure(
                        job.request_id,
                        LAVIF_INTERNAL,
                        b"Native AVIF sequence decoder panicked".to_vec(),
                    )
                });
                post_sequence_result(job.port, job.post_c_object, result);
            }
        }
    }
}

fn post_decode_result(port: i64, post_c_object: PostCObject, result: LavifDecodeResult) {
    let result = Box::into_raw(Box::new(result));
    let delivered = post_pointer(port, post_c_object, result.cast());
    if !delivered {
        unsafe { release_result(result) };
    }
}

fn post_sequence_result(port: i64, post_c_object: PostCObject, result: LavifSequenceResult) {
    let result = Box::into_raw(Box::new(result));
    let delivered = post_pointer(port, post_c_object, result.cast());
    if !delivered {
        unsafe { release_sequence_result(result) };
    }
}

fn post_pointer(port: i64, post_c_object: PostCObject, pointer: *mut c_void) -> bool {
    let mut message = DartCObject {
        type_: 3,
        value: DartCObjectValue {
            as_int64: pointer as isize as i64,
        },
    };
    unsafe { post_c_object(port, &mut message) }
}

#[no_mangle]
pub extern "C" fn lavif_async_worker_count() -> u32 {
    decode_pool().map(|pool| pool.worker_count).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn lavif_async_threads_per_worker() -> u32 {
    decode_pool()
        .map(|pool| pool.threads_per_worker)
        .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn lavif_input_allocate(length: usize) -> *mut u8 {
    catch_unwind(|| {
        if length == 0 {
            return ptr::null_mut();
        }
        let mut input = Vec::new();
        if input.try_reserve_exact(length).is_err() {
            return ptr::null_mut();
        }
        input.resize(length, 0);
        Box::into_raw(input.into_boxed_slice()) as *mut u8
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn lavif_input_release(input: *mut u8, length: usize) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        release_bytes(input, length);
    }));
}

#[no_mangle]
pub extern "C" fn lavif_decode_rgba8_async(
    input: *mut u8,
    length: usize,
    max_threads: u32,
    max_dimension: u32,
    max_pixels: u32,
    target_width: u32,
    target_height: u32,
    port: i64,
    post_c_object: PostCObject,
    request_id: u64,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if input.is_null() || length == 0 || port == 0 || request_id == 0 {
            if !input.is_null() && length != 0 {
                unsafe { release_bytes(input, length) };
            }
            return LAVIF_INVALID_INPUT;
        }
        let input = unsafe { Box::from_raw(ptr::slice_from_raw_parts_mut(input, length)) };
        let pool = match decode_pool() {
            Ok(pool) => pool,
            Err(_) => return LAVIF_INTERNAL,
        };
        let job = DecodeJob {
            request_id,
            input,
            max_threads,
            max_dimension,
            max_pixels,
            target_width,
            target_height,
            port,
            post_c_object,
        };
        pool.sender
            .send(WorkerJob::Decode(job))
            .map(|_| LAVIF_OK)
            .unwrap_or(LAVIF_INTERNAL)
    }));
    result.unwrap_or(LAVIF_INTERNAL)
}

#[no_mangle]
pub extern "C" fn lavif_sequence_open_async(
    input: *mut u8,
    length: usize,
    max_threads: u32,
    max_dimension: u32,
    max_pixels: u32,
    target_width: u32,
    target_height: u32,
    prefetch_first_frame: u8,
    port: i64,
    post_c_object: PostCObject,
    request_id: u64,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if input.is_null() || length == 0 || port == 0 || request_id == 0 {
            if !input.is_null() && length != 0 {
                unsafe { release_bytes(input, length) };
            }
            return LAVIF_INVALID_INPUT;
        }
        let input = unsafe { Box::from_raw(ptr::slice_from_raw_parts_mut(input, length)) };
        let pool = match decode_pool() {
            Ok(pool) => pool,
            Err(_) => return LAVIF_INTERNAL,
        };
        pool.sender
            .send(WorkerJob::SequenceOpen(SequenceOpenJob {
                request_id,
                input,
                max_threads,
                max_dimension,
                max_pixels,
                target_width,
                target_height,
                prefetch_first_frame: prefetch_first_frame != 0,
                port,
                post_c_object,
            }))
            .map(|_| LAVIF_OK)
            .unwrap_or(LAVIF_INTERNAL)
    }))
    .unwrap_or(LAVIF_INTERNAL)
}

#[no_mangle]
pub extern "C" fn lavif_sequence_next_async(
    handle: u64,
    port: i64,
    post_c_object: PostCObject,
    request_id: u64,
) -> i32 {
    submit_sequence_command(handle, port, post_c_object, request_id, |job| {
        WorkerJob::SequenceNext(job)
    })
}

#[no_mangle]
pub extern "C" fn lavif_sequence_reset_async(
    handle: u64,
    port: i64,
    post_c_object: PostCObject,
    request_id: u64,
) -> i32 {
    submit_sequence_command(handle, port, post_c_object, request_id, |job| {
        WorkerJob::SequenceReset(job)
    })
}

fn submit_sequence_command(
    handle: u64,
    port: i64,
    post_c_object: PostCObject,
    request_id: u64,
    wrap: impl FnOnce(SequenceCommandJob) -> WorkerJob,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if handle == 0 || port == 0 || request_id == 0 {
            return LAVIF_INVALID_INPUT;
        }
        let sequence = match sequences().lock() {
            Ok(registry) => match registry.get(&handle) {
                Some(sequence) => Arc::clone(sequence),
                None => return LAVIF_INVALID_INPUT,
            },
            Err(_) => return LAVIF_INTERNAL,
        };
        let pool = match decode_pool() {
            Ok(pool) => pool,
            Err(_) => return LAVIF_INTERNAL,
        };
        pool.sender
            .send(wrap(SequenceCommandJob {
                request_id,
                sequence,
                port,
                post_c_object,
            }))
            .map(|_| LAVIF_OK)
            .unwrap_or(LAVIF_INTERNAL)
    }))
    .unwrap_or(LAVIF_INTERNAL)
}

#[no_mangle]
pub extern "C" fn lavif_sequence_release(handle: u64) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Ok(mut registry) = sequences().lock() {
            registry.remove(&handle);
        }
    }));
}

fn error_message(error: &[c_char]) -> Vec<u8> {
    let length = error
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(error.len());
    if length == 0 {
        return b"Native AVIF decoding failed without a diagnostic".to_vec();
    }
    error[..length].iter().map(|byte| *byte as u8).collect()
}

fn leak_bytes(bytes: Vec<u8>) -> (*mut u8, usize) {
    if bytes.is_empty() {
        return (ptr::null_mut(), 0);
    }
    let boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    (Box::into_raw(boxed) as *mut u8, length)
}

struct OwnedPixels {
    _bytes: Box<[u8]>,
}

fn own_pixels(bytes: Vec<u8>) -> (*mut u8, usize, *mut c_void) {
    let mut bytes = bytes.into_boxed_slice();
    let pixels = bytes.as_mut_ptr();
    let length = bytes.len();
    let owner = Box::into_raw(Box::new(OwnedPixels { _bytes: bytes })).cast();
    (pixels, length, owner)
}

unsafe fn release_pixels(owner: *mut c_void) {
    if !owner.is_null() {
        drop(Box::from_raw(owner.cast::<OwnedPixels>()));
    }
}

unsafe fn release_bytes(bytes: *mut u8, length: usize) {
    if !bytes.is_null() && length != 0 {
        let slice = ptr::slice_from_raw_parts_mut(bytes, length);
        drop(Box::from_raw(slice));
    }
}

#[no_mangle]
pub extern "C" fn lavif_decode_result_release(result: *mut LavifDecodeResult) {
    if result.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        release_result(result);
    }));
}

unsafe fn release_result(result: *mut LavifDecodeResult) {
    let result = Box::from_raw(result);
    release_pixels(result.pixels_owner);
    release_bytes(result.error, result.error_length);
}

#[no_mangle]
pub extern "C" fn lavif_decode_result_take_pixels(result: *mut LavifDecodeResult) -> *mut c_void {
    catch_unwind(AssertUnwindSafe(|| unsafe {
        let Some(result) = result.as_mut() else {
            return ptr::null_mut();
        };
        let owner = result.pixels_owner;
        result.pixels = ptr::null_mut();
        result.pixels_length = 0;
        result.pixels_owner = ptr::null_mut();
        owner
    }))
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn lavif_sequence_result_release(result: *mut LavifSequenceResult) {
    if result.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        release_sequence_result(result);
    }));
}

unsafe fn release_sequence_result(result: *mut LavifSequenceResult) {
    let result = Box::from_raw(result);
    release_pixels(result.pixels_owner);
    release_bytes(result.error, result.error_length);
}

#[no_mangle]
pub extern "C" fn lavif_sequence_result_take_pixels(
    result: *mut LavifSequenceResult,
) -> *mut c_void {
    catch_unwind(AssertUnwindSafe(|| unsafe {
        let Some(result) = result.as_mut() else {
            return ptr::null_mut();
        };
        let owner = result.pixels_owner;
        result.pixels = ptr::null_mut();
        result.pixels_length = 0;
        result.pixels_owner = ptr::null_mut();
        owner
    }))
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn lavif_pixels_release(owner: *mut c_void) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        release_pixels(owner);
    }));
}

#[no_mangle]
pub extern "C" fn lavif_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn lavif_libavif_version() -> *const c_void {
    catch_unwind(|| unsafe { lavif_bridge_version().cast() }).unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn lavif_codec_versions() -> *const c_void {
    static CODEC_VERSIONS: OnceLock<CString> = OnceLock::new();
    catch_unwind(|| {
        CODEC_VERSIONS
            .get_or_init(|| {
                let mut buffer = [0 as c_char; 256];
                unsafe {
                    lavif_bridge_codec_versions(buffer.as_mut_ptr(), buffer.len());
                    CStr::from_ptr(buffer.as_ptr()).to_owned()
                }
            })
            .as_ptr()
            .cast()
    })
    .unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn lavif_features() -> *const c_void {
    catch_unwind(|| unsafe { lavif_bridge_features().cast() }).unwrap_or(ptr::null())
}
