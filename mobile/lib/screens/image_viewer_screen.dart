import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/nyota_service.dart';
import '../theme.dart';

/// Full-screen viewer for a gift image (large version).
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.path, this.heroTag});

  final String path;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final url = NyotaService.publicUrl(path);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Gift Image'),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(color: NyotaColors.saffron),
            ),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
