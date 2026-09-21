import 'dart:io';
import 'package:flutter/material.dart';

Widget? buildFileAvatarImage(String path, double size, Widget fallback) {
  try {
    String cleanPath = path;
    if (cleanPath.startsWith('file://')) {
      cleanPath = Uri.parse(cleanPath).toFilePath();
    }
    final file = File(cleanPath);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
  } catch (_) {}
  return null;
}
