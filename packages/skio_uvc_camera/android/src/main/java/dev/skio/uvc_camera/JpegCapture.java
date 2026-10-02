package dev.skio.uvc_camera;

import android.content.Context;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.YuvImage;

import androidx.annotation.Keep;

import com.serenegiant.usb.IFrameCallback;
import com.serenegiant.usb.UVCCamera;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Grabs one preview frame and encodes it as JPEG, either to a file or to a
 * byte array. The frame arrives on a native thread in a buffer that is reused
 * after the callback returns, and a 1080p frame is about 3 MB, so it is copied
 * and encoded here and only the file path or the JPEG bytes go to Dart.
 */
@Keep
public final class JpegCapture implements IFrameCallback {

    /** Capture result. Implemented in Dart. */
    @Keep
    public interface Callback {
        void onCaptured(String path);

        void onCapturedBytes(byte[] jpeg);

        void onError(String message);
    }

    private static final ExecutorService ENCODER = Executors.newSingleThreadExecutor();

    private final UVCCamera camera;
    private final int width;
    private final int height;
    private final int quality;
    /** Folder to write to, or null for the cache folder. Unused for bytes. */
    private final String directory;
    /** File name, or null for a timestamped name. Unused for bytes. */
    private final String fileName;
    private final boolean toBytes;
    private final Callback callback;
    private final AtomicBoolean taken = new AtomicBoolean(false);

    private JpegCapture(
            UVCCamera camera,
            int width,
            int height,
            int quality,
            String directory,
            String fileName,
            boolean toBytes,
            Callback callback) {
        this.camera = camera;
        this.width = width;
        this.height = height;
        this.quality = quality;
        this.directory = directory;
        this.fileName = fileName;
        this.toBytes = toBytes;
        this.callback = callback;
    }

    /**
     * Captures the next frame of [camera], which must be previewing, into
     * [directory]/[fileName] and reports the path. A null [directory] means
     * the app's cache folder and a null [fileName] a timestamped name.
     */
    public static void capture(
            UVCCamera camera,
            int width,
            int height,
            int quality,
            String directory,
            String fileName,
            Callback callback) {
        start(new JpegCapture(camera, width, height, quality, directory, fileName, false, callback));
    }

    /** Captures the next frame of [camera] and reports the JPEG bytes. */
    public static void captureBytes(
            UVCCamera camera, int width, int height, int quality, Callback callback) {
        start(new JpegCapture(camera, width, height, quality, null, null, true, callback));
    }

    private static void start(JpegCapture capture) {
        capture.camera.setFrameCallback(capture, UVCCamera.PIXEL_FORMAT_NV21);
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
        final int expected = width * height * 3 / 2;
        if (nv21.length < expected) {
            callback.onError("Frame too small: " + nv21.length + " < " + expected);
            return;
        }
        if (toBytes) {
            final ByteArrayOutputStream out = new ByteArrayOutputStream(expected / 4);
            if (compress(nv21, out)) callback.onCapturedBytes(out.toByteArray());
            return;
        }
        final File dir;
        if (directory != null) {
            dir = new File(directory);
        } else {
            final Context context = UvcCameraPlugin.context();
            if (context == null) {
                callback.onError("skio_uvc_camera plugin is not attached to an engine");
                return;
            }
            dir = new File(context.getCacheDir(), "uvc_camera");
        }
        if (!dir.isDirectory() && !dir.mkdirs()) {
            callback.onError("Cannot create " + dir);
            return;
        }
        final String name =
                fileName != null ? fileName : "uvc_" + System.currentTimeMillis() + ".jpg";
        final File file = new File(dir, name);
        boolean written;
        try (FileOutputStream out = new FileOutputStream(file)) {
            written = compress(nv21, out);
        } catch (IOException e) {
            written = false;
            callback.onError(String.valueOf(e.getMessage()));
        }
        if (written) {
            callback.onCaptured(file.getAbsolutePath());
        } else {
            // Don't leave a partial JPEG behind; the error is already reported.
            //noinspection ResultOfMethodCallIgnored
            file.delete();
        }
    }

    /** Writes [nv21] as JPEG to [out]; reports and returns false on failure. */
    private boolean compress(byte[] nv21, OutputStream out) {
        try {
            final YuvImage image = new YuvImage(nv21, ImageFormat.NV21, width, height, null);
            if (image.compressToJpeg(new Rect(0, 0, width, height), quality, out)) return true;
            callback.onError("JPEG encoding failed");
        } catch (RuntimeException e) {
            callback.onError(String.valueOf(e.getMessage()));
        }
        return false;
    }
}
