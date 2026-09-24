package dev.skio.uvc_camera;

import androidx.annotation.Keep;

import com.serenegiant.usb.IButtonCallback;

/**
 * Receives the camera's hardware-button events from native code and forwards
 * them to a listener implemented in Dart.
 *
 * <p>The UVC library calls the button callback directly from C++ through JNI.
 * Handing it a Dart-implemented (proxy) object crashes on real devices, so the
 * native code gets this plain Java class instead, and the Dart listener is
 * called from Java like every other skio callback.
 */
@Keep
public final class ButtonForwarder implements IButtonCallback {

    /** Hardware-button events. Implemented in Dart. */
    @Keep
    public interface Listener {
        void onButton(int button, int state);
    }

    private final Listener listener;

    public ButtonForwarder(Listener listener) {
        this.listener = listener;
    }

    @Override
    public void onButton(int button, int state) {
        try {
            listener.onButton(button, state);
        } catch (RuntimeException ignored) {
            // Never let an exception propagate back into native code.
        }
    }
}
