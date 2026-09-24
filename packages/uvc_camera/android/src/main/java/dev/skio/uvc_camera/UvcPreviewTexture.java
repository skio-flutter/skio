package dev.skio.uvc_camera;

import androidx.annotation.Keep;

import com.serenegiant.usb.UVCCamera;

import io.flutter.view.TextureRegistry;

/**
 * Renders a camera's preview into a Flutter texture and follows the texture's
 * surface lifecycle. Flutter may destroy the surface (for example when the app
 * goes to the background with Impeller) and must be able to stop the camera
 * using it synchronously, which Dart callbacks can't do, so this lives in
 * Java.
 */
@Keep
public final class UvcPreviewTexture implements TextureRegistry.SurfaceProducer.Callback {

    /** Surface lifecycle events. Implemented in Dart. */
    @Keep
    public interface Listener {
        void onPaused();

        void onResumed();

        void onError(String message);
    }

    private final UVCCamera camera;
    private final TextureRegistry.SurfaceProducer producer;
    private final Listener listener;
    private boolean released;

    public UvcPreviewTexture(UVCCamera camera, int width, int height, Listener listener) {
        final TextureRegistry textures = UvcCameraPlugin.textures();
        if (textures == null) {
            throw new IllegalStateException("uvc_camera plugin is not attached to an engine");
        }
        this.camera = camera;
        this.listener = listener;
        this.producer = textures.createSurfaceProducer();
        producer.setSize(width, height);
        producer.setCallback(this);
    }

    /** The Flutter texture id for the Texture widget. */
    public long id() {
        return producer.id();
    }

    /** Starts rendering the preview into the texture. */
    public synchronized void start() {
        if (released) return;
        camera.setPreviewDisplay(producer.getSurface());
        camera.startPreview();
    }

    @Override
    public synchronized void onSurfaceAvailable() {
        if (released) return;
        try {
            start();
            listener.onResumed();
        } catch (RuntimeException e) {
            listener.onError(String.valueOf(e.getMessage()));
        }
    }

    @Override
    public synchronized void onSurfaceCleanup() {
        if (released) return;
        try {
            camera.stopPreview();
        } catch (RuntimeException ignored) {
            // The camera may already be gone.
        }
        listener.onPaused();
    }

    /** Stops the preview and frees the texture. Safe to call more than once. */
    public synchronized void release() {
        if (released) return;
        released = true;
        try {
            camera.stopPreview();
        } catch (RuntimeException ignored) {
            // The camera may already be gone.
        }
        producer.setCallback(null);
        producer.release();
    }
}
