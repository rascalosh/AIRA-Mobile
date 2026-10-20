import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/design_system/design_system.dart';
import '../../application/annotation_controller.dart';
import '../../utils/coordinate_mapper.dart';
import '../../utils/label_png.dart';
import '../../utils/rasterizer.dart';

/// The editing surface: the MRI slice with the mask on top, a live stroke, and zoom/pan.
///
/// Gestures use raw pointer events (a gesture recogniser would wait for touch slop and lose the start of a stroke):
/// - Edit mode: one finger draws; a second finger cancels that stroke and pans/zooms. If a stylus is ever seen, the
///   stylus draws and fingers navigate.
/// - Navigate mode: one finger pans, two fingers pinch-zoom.
class MaskCanvas extends StatefulWidget {
  const MaskCanvas({super.key, required this.controller});

  final AnnotationController controller;

  @override
  State<MaskCanvas> createState() => _MaskCanvasState();
}

class _MaskCanvasState extends State<MaskCanvas> {
  static const _maxZoom = 16.0;

  final _view = TransformationController();
  final _pointers = <int, Offset>{};
  int? _drawPointer;
  var _stylusSeen = false;
  Matrix4 _navStart = Matrix4.identity();
  Map<int, Offset> _navPointers = {};
  Size _viewport = Size.zero;

  ui.Image? _fill;
  ui.Image? _userOutline;
  ui.Image? _proposalOutline;
  Object? _key;
  var _token = 0;

  AnnotationController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
    _onController();
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _view.dispose();
    _fill?.dispose();
    _userOutline?.dispose();
    _proposalOutline?.dispose();
    super.dispose();
  }

  void _onController() {
    final key = Object.hash(
      _c.z,
      _c.revision,
      _c.sliceLoading,
      _c.proposal,
      _c.opacity,
      _c.ready,
    );
    if (key == _key) return;
    _key = key;
    _rebuildImages();
  }

  /// Rebuilds the mask images for the current slice. A newer request supersedes an older one.
  Future<void> _rebuildImages() async {
    final token = ++_token;
    final slice = _c.currentSlice;
    final proposed = _c.proposalSlice;
    ui.Image? fill, user, proposal;
    if (slice != null) {
      if (proposed == null) {
        fill = await maskToImage(slice, SegColors.cyan);
      } else {
        user = await maskToImage(outline(slice), SegColors.amber);
        proposal = await maskToImage(outline(proposed), SegColors.cyan);
      }
    }
    if (!mounted || token != _token) {
      fill?.dispose();
      user?.dispose();
      proposal?.dispose();
      return;
    }
    setState(() {
      _fill?.dispose();
      _userOutline?.dispose();
      _proposalOutline?.dispose();
      _fill = fill;
      _userOutline = user;
      _proposalOutline = proposal;
    });
  }

  // -- coordinates ------------------------------------------------------------------------------------------

  Rect get _imageRect => fitImage(_viewport, _c.width, _c.height);

  VoxelMapper get _mapper => VoxelMapper(
    matrix: _view.value,
    imageRect: _imageRect,
    width: _c.width,
    height: _c.height,
  );

  Offset _voxel(Offset local) => _mapper.screenToVoxel(local);

  // -- gestures ---------------------------------------------------------------------------------------------

  bool _isStylus(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  void _down(PointerDownEvent e) {
    if (_isStylus(e)) _stylusSeen = true;
    _pointers[e.pointer] = e.localPosition;
    final canDraw = _c.editMode && _c.ready && _drawPointer == null;
    if (canDraw && (_stylusSeen ? _isStylus(e) : _pointers.length == 1)) {
      _drawPointer = e.pointer;
      _c.startStroke(_voxel(e.localPosition));
      return;
    }
    if (_drawPointer != null && !_stylusSeen) {
      // A second finger: this was not a stroke after all. Drop it and navigate with both fingers.
      _c.cancelStroke();
      _drawPointer = null;
    }
    _rebaseNavigation();
  }

  void _move(PointerMoveEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (e.pointer == _drawPointer) {
      _c.extendStroke(_voxel(e.localPosition));
    } else {
      _navigate();
    }
  }

  void _up(PointerUpEvent e) {
    if (e.pointer == _drawPointer) {
      _c.endStroke();
      _drawPointer = null;
    }
    _pointers.remove(e.pointer);
    _rebaseNavigation();
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer == _drawPointer) {
      _c.cancelStroke();
      _drawPointer = null;
    }
    _pointers.remove(e.pointer);
    _rebaseNavigation();
  }

  void _rebaseNavigation() {
    _navStart = _view.value.clone();
    _navPointers = {
      for (final e in _pointers.entries)
        if (e.key != _drawPointer) e.key: e.value,
    };
  }

  void _navigate() {
    if (_navPointers.isEmpty || _viewport.isEmpty) return;
    final ids = _navPointers.keys.take(2).toList();
    Matrix4 next;
    if (ids.length == 1) {
      final d = _pointers[ids[0]]! - _navPointers[ids[0]]!;
      next = Matrix4.translationValues(d.dx, d.dy, 0) * _navStart;
    } else {
      final a0 = _navPointers[ids[0]]!, b0 = _navPointers[ids[1]]!;
      final a1 = _pointers[ids[0]] ?? a0, b1 = _pointers[ids[1]] ?? b0;
      final d0 = (b0 - a0).distance;
      if (d0 < 1) return;
      final startScale = _navStart.getMaxScaleOnAxis();
      final scale =
          (startScale * (b1 - a1).distance / d0).clamp(1.0, _maxZoom) /
          startScale;
      final f0 = (a0 + b0) / 2, f1 = (a1 + b1) / 2;
      next =
          Matrix4.translationValues(f1.dx, f1.dy, 0) *
          Matrix4.diagonal3Values(scale, scale, 1) *
          Matrix4.translationValues(-f0.dx, -f0.dy, 0) *
          _navStart;
    }
    // Keep the centre of the image on screen so it cannot be lost.
    final centre = MatrixUtils.transformPoint(next, _imageRect.center);
    final shift = Offset(
      centre.dx.clamp(0.0, _viewport.width) - centre.dx,
      centre.dy.clamp(0.0, _viewport.height) - centre.dy,
    );
    _view.value = Matrix4.translationValues(shift.dx, shift.dy, 0) * next;
  }

  void _resetView() => _view.value = Matrix4.identity();

  // -- build ------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return ColoredBox(
      color: AiraColors.reading.background,
      child: LayoutBuilder(
        builder: (context, box) {
          _viewport = box.biggest;
          if (!c.ready || c.width == 0) {
            return Center(
              child: c.sliceError == null
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(
                      c.sliceError!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
            );
          }
          final rect = _imageRect;
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _cancel,
                  child: ValueListenableBuilder<Matrix4>(
                    valueListenable: _view,
                    builder: (context, matrix, child) =>
                        Transform(transform: matrix, child: child),
                    child: SizedBox.fromSize(
                      size: box.biggest,
                      child: Stack(
                        children: [
                          Positioned.fromRect(
                            rect: rect,
                            child: Image.memory(
                              c.currentMri!,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                          Positioned.fromRect(
                            rect: rect,
                            child: CustomPaint(
                              painter: _MaskPainter(
                                _fill,
                                _userOutline,
                                _proposalOutline,
                                c.opacity,
                              ),
                              foregroundPainter: _StrokePainter(c),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.s3,
                bottom: AppSpacing.sm,
                child: _ZoomLabel(view: _view, controller: c),
              ),
              Positioned(
                right: AppSpacing.xs,
                bottom: 0,
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _view,
                  builder: (context, matrix, _) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: matrix.isIdentity() ? 0 : 1,
                    child: IgnorePointer(
                      ignoring: matrix.isIdentity(),
                      child: AiraIconButton(
                        icon: LucideIcons.maximize,
                        label: 'Reset view',
                        filled: true,
                        onPressed: _resetView,
                      ),
                    ),
                  ),
                ),
              ),
              if (c.sliceLoading)
                const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ZoomLabel extends StatelessWidget {
  const _ZoomLabel({required this.view, required this.controller});

  final TransformationController view;
  final AnnotationController controller;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([view, controller]),
        builder: (context, _) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            'Zoom ${view.value.getMaxScaleOnAxis().toStringAsFixed(1)}×'
            '${controller.editMode ? ' · 1 finger draws, 2 fingers pan' : ''}',
            style: style?.copyWith(color: context.aira.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The mask as a crisp (unsmoothed) image. Outlines are used while a refinement proposal is shown.
class _MaskPainter extends CustomPainter {
  _MaskPainter(this.fill, this.userOutline, this.proposalOutline, this.opacity);

  final ui.Image? fill;
  final ui.Image? userOutline;
  final ui.Image? proposalOutline;
  final double opacity;

  void _draw(Canvas canvas, Size size, ui.Image? image, double alpha) {
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(0, 0, 0, alpha),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _draw(canvas, size, fill, opacity);
    _draw(canvas, size, userOutline, 1);
    _draw(canvas, size, proposalOutline, 1);
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.fill != fill ||
      old.userOutline != userOutline ||
      old.proposalOutline != proposalOutline ||
      old.opacity != opacity;
}

/// The stroke being drawn, shown as a path until the finger lifts and it is rasterized into the mask.
class _StrokePainter extends CustomPainter {
  _StrokePainter(this.controller) : super(repaint: controller.strokeTick);

  final AnnotationController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final points = controller.livePoints;
    if (points.isEmpty || controller.width == 0) return;
    final scale = size.width / controller.width;
    final path = Path()
      ..moveTo(points.first.dx * scale, points.first.dy * scale);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * scale, p.dy * scale);
    }

    if (controller.tool == EditTool.lasso) {
      path.close();
      canvas
        ..drawPath(
          path,
          Paint()..color = SegColors.amber.withValues(alpha: 0.25),
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = SegColors.amber,
        );
      return;
    }
    path.lineTo(
      points.last.dx * scale + 0.01,
      points.last.dy * scale,
    ); // a tap still draws a dot
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = controller.brushSize * scale
        ..color = controller.tool == EditTool.eraser
            ? const Color(0x99F2777F)
            : SegColors.amber.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.controller != controller;
}
