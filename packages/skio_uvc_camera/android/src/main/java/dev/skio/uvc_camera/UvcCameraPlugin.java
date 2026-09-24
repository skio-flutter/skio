package dev.skio.uvc_camera;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.provider.Settings;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.TextureRegistry;

/**
 * Gives Dart the Flutter objects JNI can't reach on its own: the texture
 * registry and the Activity's permission result. Everything else is called
 * from Dart directly through jnigen.
 */
@Keep
public final class UvcCameraPlugin
        implements FlutterPlugin, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    /** Receives the CAMERA permission result. Implemented in Dart. */
    @Keep
    public interface PermissionCallback {
        void onResult(boolean granted, boolean permanentlyDenied);
    }

    private static final int REQUEST_CODE = 0x5c10;

    private static volatile TextureRegistry textures;
    private static volatile Context appContext;
    private static volatile ActivityPluginBinding activityBinding;
    private static PermissionCallback pendingCallback;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        textures = binding.getTextureRegistry();
        appContext = binding.getApplicationContext();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        textures = null;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
    }

    /** The engine's texture registry, or null before the plugin attaches. */
    public static TextureRegistry textures() {
        return textures;
    }

    /** The application context, or null before the plugin attaches. */
    public static Context context() {
        return appContext;
    }

    public static boolean hasCameraPermission() {
        final Context context = appContext;
        return context != null
                && context.checkSelfPermission(Manifest.permission.CAMERA)
                        == PackageManager.PERMISSION_GRANTED;
    }

    /**
     * Asks for CAMERA if needed. Answers at once when already granted or when
     * there is no Activity to show the dialog.
     */
    public static synchronized void requestCameraPermission(PermissionCallback callback) {
        if (hasCameraPermission()) {
            callback.onResult(true, false);
            return;
        }
        final ActivityPluginBinding binding = activityBinding;
        if (binding == null || pendingCallback != null) {
            callback.onResult(false, false);
            return;
        }
        pendingCallback = callback;
        binding.getActivity()
                .requestPermissions(new String[] {Manifest.permission.CAMERA}, REQUEST_CODE);
    }

    @Override
    public boolean onRequestPermissionsResult(
            int requestCode, @NonNull String[] permissions, @NonNull int[] results) {
        if (requestCode != REQUEST_CODE) return false;
        final PermissionCallback callback;
        synchronized (UvcCameraPlugin.class) {
            callback = pendingCallback;
            pendingCallback = null;
        }
        if (callback == null) return true;
        final boolean granted =
                results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED;
        // After a denial, Android stops showing the dialog once it no longer
        // wants to show a rationale: the user chose "Don't ask again".
        final Activity activity = activityBinding == null ? null : activityBinding.getActivity();
        final boolean permanentlyDenied = !granted
                && activity != null
                && !activity.shouldShowRequestPermissionRationale(Manifest.permission.CAMERA);
        callback.onResult(granted, permanentlyDenied);
        return true;
    }

    /** Opens this app's page in system settings. Returns false on failure. */
    public static boolean openAppSettings() {
        final Context context = appContext;
        if (context == null) return false;
        try {
            final Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", context.getPackageName(), null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            return true;
        } catch (RuntimeException e) {
            return false;
        }
    }
}
