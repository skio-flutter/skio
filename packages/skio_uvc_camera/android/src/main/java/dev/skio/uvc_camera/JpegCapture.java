package dev.skio.uvc_camera;

import android.content.Context;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.YuvImage;

import androidx.annotation.Keep;

import com.serenegiant.usb.IFrameCallback;
import com.serenegiant.usb.UVCCamera;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Grabs one preview frame and writes it as a JPEG file. The frame arrives on
 * a native thread in a buffer that is reused after the callback returns, and
 * a 1080p frame is about 3 MB, so it is copied and encoded here and only the
 * file path goes to Dart.
 */
@Keep
public final class JpegCapture implements IFrameCallback {

    /** Capture result. Implemented in Dart. */
    @Keep
    public interface Callback {
        void onCaptured(String path);

        void onError(String message);
    }

    private static final ExecutorService ENCODER = Executors.newSingleThreadExecutor();

    private final UVCCamera camera;
    private final int width;
    private final int height;
    private final int quality;
    private final Callback callback;
    private final AtomicBoolean taken = new AtomicBoolean(false);

    private JpegCapture(UVCCamera camera, int width, int height, int quality, Callback callback) {
        this.camera = camera;
        this.width = width;
        this.height = height;
        this.quality = quality;
        this.callback = callback;
    }

    /** Captures the next frame of [camera], which must be previewing. */
    public static void capture(
            UVCCamera camera, int width, int height, int quality, Callback callback) {
        camera.setFrameCallback(
                new JpegCapture(camera, width, height, quality, callback),
                UVCCamera.PIXEL_FORMAT_NV21);
    }

    @Override
    public void onFrame(ByteBuffer frame) {
        if (taken.getAndSet(true)) return;
        final byte[] nv21 = new byte[frame.remaining()];
        frame.get(nv21);
        ENCODER.execute(() -> {
            // Stop frame delivery off the native callback thread.
            try {
                camera.setFrameCallback(null, 0);
            } catch (RuntimeException ignored) {
                // The camera may already be closed.
            }
            encode(nv21);
        });
    }

    private void encode(byte[] nv21) {
        final Context context = UvcCameraPlugin.context();
        if (context == null) {
            callback.onError("skio_uvc_camera plugin is not attached to an engine");
            return;
        }
        final int expected = width * height * 3 / 2;
        if (nv21.length < expected) {
            callback.onError("Frame too small: " + nv21.length + " < " + expected);
            return;
        }
        final File dir = new File(context.getCacheDir(), "uvc_camera");
        if (!dir.isDirectory() && !dir.mkdirs()) {
            callback.onError("Cannot create " + dir);
            return;
        }
        final File file = new File(dir, "uvc_" + System.currentTimeMillis() + ".jpg");
        try (FileOutputStream out = new FileOutputStream(file)) {
            final YuvImage image = new YuvImage(nv21, ImageFormat.NV21, width, height, null);
            if (!image.compressToJpeg(new Rect(0, 0, width, height), quality, out)) {
                callback.onError("JPEG encoding failed");
                return;
            }
        } catch (IOException | RuntimeException e) {
            callback.onError(String.valueOf(e.getMessage()));
            return;
        }
        callback.onCaptured(file.getAbsolutePath());
    }
}
