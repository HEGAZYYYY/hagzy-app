import 'dart:convert';
import 'package:flutter/material.dart';

class HagzySmartImage extends StatelessWidget {
  const HagzySmartImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.errorWidget,
    this.loadingBuilder,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Widget? errorWidget;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) {
      return errorWidget ?? const SizedBox.shrink();
    }
    if (trimmed.startsWith('data:image')) {
      try {
        final commaIdx = trimmed.indexOf(',');
        if (commaIdx != -1) {
          final base64Str = trimmed.substring(commaIdx + 1);
          final bytes = base64Decode(base64Str);
          return Image.memory(
            bytes,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
          );
        }
      } catch (_) {}
    }
    return Image.network(
      trimmed,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      loadingBuilder: loadingBuilder,
      errorBuilder: (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
    );
  }
}
