import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

class CameraService {
  static final ImagePicker _picker = ImagePicker();

  /// Whether current platform is desktop (where camera is not supported by image_picker)
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Resizes any raw image bytes to max 256x256 PNG and returns a compact Base64 URI.
  /// This guarantees payloads remain under ~30KB and load instantly everywhere.
  static Future<String> _resizeAndEncode(Uint8List rawBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: 256,
        targetHeight: 256,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final resizedBytes = byteData.buffer.asUint8List();
        return 'data:image/png;base64,${base64Encode(resizedBytes)}';
      }
    } catch (e) {
      debugPrint('CameraService._resizeAndEncode error: $e');
    }
    return 'data:image/jpeg;base64,${base64Encode(rawBytes)}';
  }

  /// Captures a photo using the device camera.
  /// Falls back smoothly to file/gallery picker on desktop or if camera is unavailable.
  static Future<String?> capturePhotoWithCamera() async {
    if (isDesktop) {
      return pickPhotoFromGallery();
    }
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );

      if (photo == null) return null;
      final bytes = await photo.readAsBytes();
      return await _resizeAndEncode(bytes);
    } catch (e) {
      debugPrint('CameraService.capturePhotoWithCamera fallback to gallery: $e');
      return pickPhotoFromGallery();
    }
  }

  /// Picks an image from device gallery / files and scales it down to 256x256.
  static Future<String?> pickPhotoFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return null;
      final bytes = await image.readAsBytes();
      return await _resizeAndEncode(bytes);
    } catch (e) {
      debugPrint('CameraService.pickPhotoFromGallery error: $e');
      rethrow;
    }
  }

  static const List<String> presetAvatars = [
    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
    'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=150',
    'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=150',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
  ];

  static String formatErrorMessage(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('missingpluginexception')) {
      return 'Photo access is initializing or reloading. Please refresh the browser or restart the app.';
    }
    if (s.contains('camera_access_denied') || s.contains('permission_denied') || s.contains('permission')) {
      return 'Camera or photo permission was denied. Please allow access in your device or browser settings.';
    }
    if (s.contains('no_available_camera') || s.contains('not supported')) {
      return 'Camera is not available on this device. Please choose a photo from files or gallery.';
    }
    return 'Could not access photo: ${e.toString().replaceAll('Exception: ', '')}';
  }

  /// Shows a modal bottom sheet allowing the user to select Camera or Gallery.
  static Future<String?> showPhotoSourceSheet(
    BuildContext context, {
    String title = 'Select Profile Picture',
  }) async {
    return showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'A photo is required for your user profile.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            // On Desktop: Gallery / File picker is the primary option
            if (isDesktop) ...[
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.electricLime.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.folder_open, color: AppTheme.electricLime, size: 24),
                ),
                title: const Text(
                  'Choose Image File',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Select a photo or image from your computer',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: AppTheme.surfaceElevated,
                onTap: () async {
                  try {
                    final res = await pickPhotoFromGallery();
                    if (ctx.mounted) {
                      Navigator.pop(ctx, res);
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(formatErrorMessage(e)),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                    }
                  }
                },
              ),
            ] else ...[
              // On Mobile/Web: Camera & Gallery options
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.electricLime.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: AppTheme.electricLime, size: 24),
                ),
                title: const Text(
                  'Take Photo (Camera)',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Use your device camera to take a new selfie',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: AppTheme.surfaceElevated,
                onTap: () async {
                  try {
                    final res = await capturePhotoWithCamera();
                    if (ctx.mounted) {
                      Navigator.pop(ctx, res);
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(formatErrorMessage(e)),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library, color: AppTheme.textSecondary, size: 24),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Select an existing image from your device',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: AppTheme.surfaceElevated,
                onTap: () async {
                  try {
                    final res = await pickPhotoFromGallery();
                    if (ctx.mounted) {
                      Navigator.pop(ctx, res);
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(formatErrorMessage(e)),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Or choose a preset avatar:',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: presetAvatars.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final avatarUrl = presetAvatars[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx, avatarUrl);
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.border, width: 1.5),
                      ),
                      child: ClipOval(
                        child: Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
