import 'package:flutter/widgets.dart';

/// Converts a touch position to a voxel position, undoing the view transform (zoom and pan).
///
///   screen point -> (inverse of [matrix]) -> scene point -> (position inside [imageRect]) -> voxel point
///
/// "Scene" is the coordinate space the transformed content is laid out in, and [imageRect] is where the slice
/// image sits in it. An off-by-a-few-pixels mapping puts strokes in the wrong place, which matters for a small
/// lesion, so this is covered by unit tests.
class VoxelMapper {
  const VoxelMapper({
    required this.matrix,
    required this.imageRect,
    required this.width,
    required this.height,
  });

  final Matrix4 matrix;
  final Rect imageRect;
  final int width;
  final int height;

  Offset screenToScene(Offset screen) {
    final inverse = Matrix4.tryInvert(matrix) ?? Matrix4.identity();
    return MatrixUtils.transformPoint(inverse, screen);
  }

  Offset sceneToVoxel(Offset scene) => Offset(
    (scene.dx - imageRect.left) / imageRect.width * width,
    (scene.dy - imageRect.top) / imageRect.height * height,
  );

  Offset voxelToScene(Offset voxel) => Offset(
    imageRect.left + voxel.dx / width * imageRect.width,
    imageRect.top + voxel.dy / height * imageRect.height,
  );

  Offset screenToVoxel(Offset screen) => sceneToVoxel(screenToScene(screen));

  /// Whether a voxel point lies on the slice.
  bool contains(Offset voxel) =>
      voxel.dx >= 0 && voxel.dy >= 0 && voxel.dx < width && voxel.dy < height;
}

/// The largest rectangle with the slice's aspect ratio that fits in [viewport], centred.
Rect fitImage(Size viewport, int width, int height) {
  final scale = (viewport.width / width) < (viewport.height / height)
      ? viewport.width / width
      : viewport.height / height;
  final size = Size(width * scale, height * scale);
  return Offset(
        (viewport.width - size.width) / 2,
        (viewport.height - size.height) / 2,
      ) &
      size;
}
