import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/mask_slice.dart';

/// Decodes the server's label PNG (8-bit gray, pixel value = label) into labels.
Future<MaskSlice> decodeLabelPng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final labels = Uint8List(image.width * image.height);
      for (var i = 0; i < labels.length; i++) {
        labels[i] = rgba.getUint8(i * 4); // gray: R = G = B = label
      }
      return MaskSlice(image.width, image.height, labels);
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> _fromRgba(Uint8List rgba, int width, int height) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// Encodes labels as a lossless PNG for upload. The image is opaque gray (R = G = B = label); the server reads
/// the red channel, so no label value is ever changed by transparency handling.
Future<Uint8List> encodeLabelPng(MaskSlice slice) async {
  final rgba = Uint8List(slice.labels.length * 4);
  for (var i = 0; i < slice.labels.length; i++) {
    final v = slice.labels[i];
    rgba[i * 4] = v;
    rgba[i * 4 + 1] = v;
    rgba[i * 4 + 2] = v;
    rgba[i * 4 + 3] = 255;
  }
  final image = await _fromRgba(rgba, slice.width, slice.height);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// A transparent image with [color] wherever the label is non-zero, for drawing the mask over the MRI.
Future<ui.Image> maskToImage(MaskSlice slice, ui.Color color) {
  final rgba = Uint8List(slice.labels.length * 4);
  for (var i = 0; i < slice.labels.length; i++) {
    if (slice.labels[i] == 0) continue;
    rgba[i * 4] = (color.r * 255).round();
    rgba[i * 4 + 1] = (color.g * 255).round();
    rgba[i * 4 + 2] = (color.b * 255).round();
    rgba[i * 4 + 3] = 255;
  }
  return _fromRgba(rgba, slice.width, slice.height);
}

/// A transparent image showing where two masks differ: [onlyA] where only [a] has mask, [onlyB] where only [b]
/// has it, and a faint [both] where they agree.
Future<ui.Image> differenceImage(
  MaskSlice a,
  MaskSlice b, {
  ui.Color onlyA = const ui.Color(0xFFF59E0B),
  ui.Color onlyB = const ui.Color(0xFF22D3EE),
  ui.Color both = const ui.Color(0x66E8EAF2),
}) {
  final rgba = Uint8List(a.labels.length * 4);
  for (var i = 0; i < a.labels.length; i++) {
    final inA = a.labels[i] != 0, inB = b.labels[i] != 0;
    if (!inA && !inB) continue;
    final c = inA && inB ? both : (inA ? onlyA : onlyB);
    rgba[i * 4] = (c.r * 255).round();
    rgba[i * 4 + 1] = (c.g * 255).round();
    rgba[i * 4 + 2] = (c.b * 255).round();
    rgba[i * 4 + 3] = (c.a * 255).round();
  }
  return _fromRgba(rgba, a.width, a.height);
}
