package org.discourse.video_optimizer;

import android.content.Context;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.net.Uri;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.effect.Presentation;
import androidx.media3.transformer.Composition;
import androidx.media3.transformer.DefaultEncoderFactory;
import androidx.media3.transformer.EditedMediaItem;
import androidx.media3.transformer.EditedMediaItemSequence;
import androidx.media3.transformer.Effects;
import androidx.media3.transformer.ExportException;
import androidx.media3.transformer.ExportResult;
import androidx.media3.transformer.Transformer;
import androidx.media3.transformer.VideoEncoderSettings;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.IOException;
import java.util.Collections;

/** Engine-scoped optional exporter. No activities, permissions, or network I/O. */
@UnstableApi
public final class VideoOptimizerPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private final Handler main = new Handler(Looper.getMainLooper());
  private HandlerThread thread;
  private Handler worker;
  private MethodChannel channel;
  private Context context;
  // Accessed only on the worker looper, including Transformer callbacks.
  private Job active;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    thread = new HandlerThread("DiscourseVideoOptimizer");
    thread.start();
    worker = new Handler(thread.getLooper());
    channel = new MethodChannel(binding.getBinaryMessenger(), "org.discourse.native/video_optimizer");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    if (call.method.equals("isAvailable")) { result.success(true); return; }
    Number id = call.argument("id");
    if (id == null) { result.success(false); return; }
    if (call.method.equals("cancel")) {
      worker.post(() -> {
        if (active != null && active.id == id.longValue()) active.finish(false);
        // Transformer.cancel() has released its codecs before acknowledging.
        main.post(() -> result.success(null));
      });
    } else if (call.method.equals("optimize")) {
      String input = call.argument("inputPath");
      String output = call.argument("outputPath");
      worker.post(() -> {
        if (active != null || input == null || output == null || input.equals(output)
            || !new File(input).isAbsolute() || !new File(output).isAbsolute()
            || new File(output).exists()) {
          main.post(() -> result.success(false));
          return;
        }
        Job job = new Job(id.longValue(), new File(input), new File(output), result);
        active = job;
        job.start();
      });
    } else {
      result.notImplemented();
    }
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    worker.post(() -> {
      if (active != null) active.finish(false);
      thread.quitSafely();
    });
  }

  private final class Job {
    final long id;
    final File input;
    final File output;
    final MethodChannel.Result reply;
    final Runnable timeout = () -> finish(false);
    Transformer transformer;
    Info source;
    boolean finished;

    Job(long id, File input, File output, MethodChannel.Result reply) {
      this.id = id;
      this.input = input;
      this.output = output;
      this.reply = reply;
    }

    void start() {
      worker.postDelayed(timeout, 600_000);
      try {
        source = Info.read(input);
        VideoPolicy policy = new VideoPolicy(source.width, source.height);
        EditedMediaItem item = new EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input)))
            .setEffects(new Effects(Collections.emptyList(), Collections.singletonList(
                Presentation.createForWidthAndHeight(policy.width, policy.height,
                    Presentation.LAYOUT_SCALE_TO_FIT))))
            .build();
        transformer = new Transformer.Builder(context)
            .setLooper(worker.getLooper())
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(new DefaultEncoderFactory.Builder(context)
                .setRequestedVideoEncoderSettings(new VideoEncoderSettings.Builder()
                    .setBitrate(policy.bitrate).build())
                .setEnableFallback(false).build())
            .addListener(new Transformer.Listener() {
              @Override
              public void onCompleted(Composition composition, ExportResult result) {
                if (finished) return;
                try {
                  Info encoded = Info.read(output);
                  finish(encoded.h264 && encoded.aac && output.length() > 0
                      && output.length() < input.length()
                      && VideoPolicy.validOutput(source.width, source.height, source.durationUs,
                          source.audioTracks, encoded.width, encoded.height, encoded.durationUs,
                          encoded.audioTracks));
                } catch (Exception | LinkageError error) { finish(false); }
              }

              @Override
              public void onError(Composition composition, ExportResult result, ExportException error) {
                finish(false);
              }
            }).build();
        EditedMediaItemSequence sequence = source.audioTracks == 0
            ? EditedMediaItemSequence.withVideoFrom(Collections.singletonList(item))
            : EditedMediaItemSequence.withAudioAndVideoFrom(Collections.singletonList(item));
        Composition composition = new Composition.Builder(sequence)
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL).build();
        transformer.start(composition, output.getAbsolutePath());
      } catch (Exception | LinkageError error) { finish(false); }
    }

    void finish(boolean success) {
      if (finished) return;
      finished = true;
      worker.removeCallbacks(timeout);
      if (transformer != null) {
        try { transformer.cancel(); } catch (RuntimeException ignored) { }
        transformer = null;
      }
      if (!success) output.delete();
      if (active == this) active = null;
      main.post(() -> reply.success(success));
    }
  }

  private static final class Info {
    int width;
    int height;
    long durationUs;
    int audioTracks;
    boolean h264;
    boolean aac = true;

    static Info read(File file) throws IOException {
      MediaExtractor extractor = new MediaExtractor();
      try {
        extractor.setDataSource(file.getAbsolutePath());
        Info info = new Info();
        int videoTracks = 0;
        for (int i = 0; i < extractor.getTrackCount(); i++) {
          MediaFormat format = extractor.getTrackFormat(i);
          String mime = format.getString(MediaFormat.KEY_MIME);
          if (mime == null) continue;
          if (mime.startsWith("video/")) {
            videoTracks++;
            info.width = format.getInteger(MediaFormat.KEY_WIDTH);
            info.height = format.getInteger(MediaFormat.KEY_HEIGHT);
            int rotation = format.containsKey(MediaFormat.KEY_ROTATION)
                ? format.getInteger(MediaFormat.KEY_ROTATION) : 0;
            if (Math.abs(rotation) % 180 == 90) {
              int swap = info.width; info.width = info.height; info.height = swap;
            }
            info.durationUs = format.getLong(MediaFormat.KEY_DURATION);
            info.h264 = MimeTypes.VIDEO_H264.equals(mime);
          } else if (mime.startsWith("audio/")) {
            info.audioTracks++;
            info.aac &= MimeTypes.AUDIO_AAC.equals(mime);
          }
        }
        if (videoTracks != 1 || info.audioTracks > 1 || info.durationUs <= 0) {
          throw new IOException("Unsupported video tracks");
        }
        return info;
      } finally { extractor.release(); }
    }
  }
}
