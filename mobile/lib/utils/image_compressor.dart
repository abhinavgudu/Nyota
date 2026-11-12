import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Compresses and resizes a picked image before upload.
/// Returns JPEG bytes capped to ~1024px on the long edge at quality 70.
class ImageCompressor {
  static Future<Uint8List> compress(Uint8List original) async {
    // Resize to max 1024px on the long edge and re-encode as JPEG.
    final result = await FlutterImageCompress.compressWithList(
      original,
      minWidth: 1024,
      minHeight: 1024,
      quality: 70,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    // If compression made the file bigger (tiny images), use the smaller one.
    return result.lengthInBytes <= original.length ? result : original;
  }
}
