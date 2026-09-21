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
                          content: Text('Could not select image: $e'),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                    }
                  }
                },
              ),
            ] else ...[
              // On Mobile: Camera & Gallery options
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
                          content: Text('Could not access camera: $e'),
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
                          content: Text('Could not select image: $e'),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
