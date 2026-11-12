import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/nyota_service.dart';
import '../screens/image_viewer_screen.dart';

/// Tappable gift thumbnail shown in register cards.
class GiftThumb extends StatelessWidget {
  const GiftThumb({super.key, required this.path, this.size = 40});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ImageViewerScreen(path: path),
          ));
        },
        child: CachedNetworkImage(
          imageUrl: NyotaService.publicUrl(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: size,
            height: size,
            color: const Color(0xFFF3F0FA),
            child: const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: size,
            height: size,
            color: const Color(0xFFF3F0FA),
            child: const Icon(Icons.broken_image, size: 16),
          ),
        ),
      ),
    );
  }
}
