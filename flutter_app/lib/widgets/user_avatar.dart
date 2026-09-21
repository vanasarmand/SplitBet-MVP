import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'avatar_file_image.dart';

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final String? displayName;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;
  final bool showEditBadge;
  final bool showWinnerCrown;
  final VoidCallback? onTap;
  final VoidCallback? onEditTap;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 20,
    this.displayName,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
    this.showEditBadge = false,
    this.showWinnerCrown = false,
    this.onTap,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? AppTheme.electricLime;
    final size = radius * 2;

    Widget avatarContent = _buildImageContent();

    Widget avatarWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(color: effectiveBorderColor, width: borderWidth)
            : null,
      ),
      child: ClipOval(child: avatarContent),
    );

    if (onTap != null) {
      avatarWidget = GestureDetector(
        onTap: onTap,
        child: avatarWidget,
      );
    }

    if (!showEditBadge && !showWinnerCrown) {
      return avatarWidget;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        if (showWinnerCrown)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: EdgeInsets.all(radius * 0.15),
              decoration: BoxDecoration(
                color: AppTheme.gold,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.surface, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                Icons.emoji_events,
                size: radius * 0.6,
                color: Colors.black,
              ),
            ),
          ),
        if (showEditBadge)
          Positioned(
            bottom: -2,
            right: -2,
            child: GestureDetector(
              onTap: onEditTap ?? onTap,
              child: Container(
                padding: EdgeInsets.all(radius * 0.18),
                decoration: BoxDecoration(
                  color: AppTheme.electricLime,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.surface, width: 2),
                ),
                child: Icon(
                  Icons.camera_alt,
                  size: radius * 0.55,
                  color: Colors.black,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageContent() {
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) {
      return _buildFallback();
    }

    final size = radius * 2;

    // 1. Base64 Data URI or raw base64 string
    if (url.startsWith('data:') || _isLikelyBase64(url)) {
      try {
        String base64String = url;
        final commaIndex = url.indexOf(',');
        if (commaIndex != -1) {
          base64String = url.substring(commaIndex + 1);
        }
        // Sanitize: remove whitespace/newlines, convert any space back to '+', and normalize padding
        base64String = base64String.replaceAll(RegExp(r'\s+'), '').replaceAll(' ', '+');
        base64String = base64.normalize(base64String);
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: size,
          height: size,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      } catch (_) {
        return _buildFallback();
      }
    }

    // 2. Local File Path (e.g. file://..., /data/..., C:\...)
    if (url.startsWith('file://') ||
        url.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(url)) {
      final fileWidget = buildFileAvatarImage(url, size, _buildFallback());
      if (fileWidget != null) {
        return fileWidget;
      }
    }

    // 3. Remote Network URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: size,
        height: size,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: AppTheme.surfaceLight,
            child: const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.electricLime,
                ),
              ),
            ),
          );
        },
      );
    }

    return _buildFallback();
  }

  bool _isLikelyBase64(String str) {
    if (str.length < 40) return false;
    if (str.startsWith('http://') || str.startsWith('https://') || str.startsWith('file://')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(str.substring(0, 40));
  }

  Widget _buildFallback() {
    final initial = (displayName != null && displayName!.trim().isNotEmpty)
        ? displayName!.trim()[0].toUpperCase()
        : null;

    return Container(
      color: AppTheme.surfaceLight,
      child: Center(
        child: initial != null
            ? Text(
                initial,
                style: TextStyle(
                  color: AppTheme.electricLime,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.85,
                ),
              )
            : Icon(
                Icons.person,
                color: AppTheme.textMuted,
                size: radius * 1.1,
              ),
      ),
    );
  }
}
