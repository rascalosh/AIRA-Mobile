import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/annotation_repository.dart';
import '../domain/mask_slice.dart';
import '../utils/label_png.dart';
import '../utils/rasterizer.dart';

enum EditTool { brush, eraser, lasso }

/// A refinement the server proposed for one slice; nothing changes until the user accepts it.
class RefineProposal {
  const RefineProposal(this.slice, this.labels, this.changedPixels);

  final int slice;
  final Uint8List labels;

  /// How many pixels differ from the user's edit (0: nothing to refine).
  final int changedPixels;
}

/// State and logic of the mask editor: slices loaded from the server, edits with undo/redo, the set of slices
/// to save, saving as a new version, and refinement proposals. It holds no UI types so it can be tested directly.
///
/// Edits live in memory until saved. `# ponytail: they are lost if the app is killed; persist them if that matters.`
class AnnotationController extends ChangeNotifier {
  AnnotationController({
    required this.repository,
    required this.studyId,
    required this.t2wResourceId,
    required this.sliceCount,
    required this.voxelMm,
  });

  static const maxHistory = 50;
  static const label = 1;

  final AnnotationRepository repository;
  final String studyId;
  final String t2wResourceId;
  final int sliceCount;

  /// Millimetres per voxel, to show the brush size in mm.
  final double voxelMm;

  // -- loading ----------------------------------------------------------------------------------------------
  bool loading = true;
  String? loadError;
  bool sliceLoading = false;
  String? sliceError;
  List<MaskVersion> versions = const [];

  /// The version being edited: always the latest, which is the only one the server accepts a save on.
  MaskVersion? base;

  // -- view state -------------------------------------------------------------------------------------------
  int z = 0;
  EditTool tool = EditTool.brush;
  bool editMode = true;

  /// Brush diameter in voxels.
  double brushSize = 6;
  double opacity = 0.4;

  /// Bumped whenever the current slice's pixels change, so the canvas knows to redraw the mask.
  int revision = 0;

  /// The stroke being drawn, in voxel coordinates. Repaints go through [strokeTick], not [notifyListeners].
  final List<Offset> livePoints = [];
  final strokeTick = ValueNotifier<int>(0);

  // -- saving -----------------------------------------------------------------------------------------------
  bool saving = false;
  String? saveError;
  bool conflict = false;
  String? savedName;

  // -- refinement -------------------------------------------------------------------------------------------
  double refineBand = 3;
  bool refining = false;
  String? refineError;
  RefineProposal? proposal;

  final _slices = <int, MaskSlice>{};
  final _baseline = <int, Uint8List>{};
  final _mri = <int, Uint8List>{};
  final _undo = <int, List<EditOp>>{};
  final _redo = <int, List<EditOp>>{};
  final _dirty = <int>{};
  final _refined = <int>{};
  final _pending = <int, Future<void>>{};
  var _navToken = 0;

  MaskSlice? get currentSlice => _slices[z];
  Uint8List? get currentMri => _mri[z];
  bool get ready => currentSlice != null && currentMri != null;
  int get width => currentSlice?.width ?? 0;
  int get height => currentSlice?.height ?? 0;

  List<int> get dirtySlices => _dirty.toList()..sort();
  bool get hasUnsavedChanges => _dirty.isNotEmpty;
  bool get canUndo => _undo[z]?.isNotEmpty ?? false;
  bool get canRedo => _redo[z]?.isNotEmpty ?? false;
  int get undoSteps => _undo.values.fold(0, (sum, ops) => sum + ops.length);
  bool get isCurrentSliceDirty => _dirty.contains(z);
  String get nextVersionName =>
      'Corrected v${versions.where((v) => !v.isAi).length + 1}';
  MaskSlice? get proposalSlice =>
      proposal == null ? null : MaskSlice(width, height, proposal!.labels);

  // -- loading ----------------------------------------------------------------------------------------------

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      versions = await repository.getVersions(studyId);
      if (versions.isEmpty) {
        throw const ApiException(
          'Run the AI segmentation before editing the mask.',
        );
      }
      base = versions.last;
      final marks = base!.slicesWithMask;
      z = marks.isNotEmpty
          ? marks.first.clamp(0, sliceCount - 1)
          : sliceCount ~/ 2;
      await _ensureSlice(z);
    } on ApiException catch (e) {
      loadError = e.message;
    }
    loading = false;
    revision++;
    notifyListeners();
  }

  /// Throws away local edits and loads the latest version from the server (after a conflict).
  Future<void> reloadLatest() async {
    _slices.clear();
    _baseline.clear();
    _mri.clear();
    _undo.clear();
    _redo.clear();
    _dirty.clear();
    _refined.clear();
    _pending.clear();
    livePoints.clear();
    proposal = null;
    conflict = false;
    saveError = null;
    await load();
  }

  Future<void> _ensureSlice(int n) {
    if (_slices.containsKey(n) && _mri.containsKey(n)) return Future.value();
    // The callback must not return the removed future: whenComplete would then wait on itself forever.
    return _pending[n] ??= _fetch(n).whenComplete(() {
      _pending.remove(n);
    });
  }

  Future<void> _fetch(int n) async {
    final results = await Future.wait([
      repository.getLabelSlice(base!.versionId, n),
      repository.getFullSlice(t2wResourceId, n),
    ]);
    final slice = await decodeLabelPng(results[0]);
    _slices[n] ??= slice; // never replace a slice that already has local edits
    _baseline[n] ??= Uint8List.fromList(slice.labels);
    _mri[n] = results[1];
  }

  Future<void> goToSlice(int n) async {
    final target = n.clamp(0, sliceCount - 1);
    if (target == z && ready) return;
    cancelStroke();
    proposal = null;
    refineError = null;
    z = target;
    sliceError = null;
    final token = ++_navToken;
    if (!(_slices.containsKey(z) && _mri.containsKey(z))) {
      sliceLoading = true;
      revision++;
      notifyListeners();
      try {
        await _ensureSlice(z);
      } on ApiException catch (e) {
        if (token == _navToken) sliceError = e.message;
      }
    }
    if (token != _navToken) return; // the user has moved on to another slice
    sliceLoading = false;
    revision++;
    notifyListeners();
    for (final next in [z - 1, z + 1]) {
      if (next >= 0 && next < sliceCount) {
        unawaited(_ensureSlice(next).catchError((_) {}));
      }
    }
  }

  // -- tools ------------------------------------------------------------------------------------------------

  void setTool(EditTool value) {
    tool = value;
    notifyListeners();
  }

  void setEditMode(bool value) {
    cancelStroke();
    editMode = value;
    notifyListeners();
  }

  void setBrushSize(double value) {
    brushSize = value;
    notifyListeners();
  }

  void setOpacity(double value) {
    opacity = value;
    notifyListeners();
  }

  // -- drawing ----------------------------------------------------------------------------------------------

  bool get _canDraw => editMode && ready && !saving && !refining;

  void startStroke(Offset voxel) {
    if (!_canDraw) return;
    proposal = null;
    livePoints
      ..clear()
      ..add(voxel);
    strokeTick.value++;
  }

  void extendStroke(Offset voxel) {
    if (livePoints.isEmpty) return;
    livePoints.add(voxel);
    strokeTick.value++;
  }

  /// Drops the stroke in progress without changing the mask (e.g. a second finger came down).
  void cancelStroke() {
    if (livePoints.isEmpty) return;
    livePoints.clear();
    strokeTick.value++;
  }

  /// Rasterizes the stroke into the mask as one undoable edit.
  void endStroke() {
    final points = List<Offset>.of(livePoints);
    livePoints.clear();
    strokeTick.value++;
    final slice = currentSlice;
    if (slice == null || points.isEmpty) return;
    final radius = (brushSize / 2).clamp(0.5, 100.0);
    final op = switch (tool) {
      EditTool.brush => paintStroke(
        slice,
        points,
        radius: radius,
        value: label,
      ),
      EditTool.eraser => paintStroke(slice, points, radius: radius, value: 0),
      EditTool.lasso => fillPolygon(slice, points, value: label),
    };
    if (op != null) _record(op);
  }

  // -- history ----------------------------------------------------------------------------------------------

  /// Remembers an edit that has already been applied to the current slice.
  void _record(EditOp op) {
    proposal = null;
    final undo = _undo.putIfAbsent(z, () => []);
    undo.add(op);
    if (undo.length > maxHistory) undo.removeAt(0);
    _redo[z]?.clear();
    _changed();
  }

  void _changed() {
    final slice = _slices[z]!;
    if (sameLabels(slice.labels, _baseline[z]!)) {
      _dirty.remove(z);
    } else {
      _dirty.add(z);
    }
    revision++;
    notifyListeners();
  }

  void undo() {
    final ops = _undo[z];
    if (ops == null || ops.isEmpty) return;
    final op = ops.removeLast();
    op.undo(currentSlice!.labels);
    (_redo[z] ??= []).add(op);
    proposal = null;
    _changed();
  }

  void redo() {
    final ops = _redo[z];
    if (ops == null || ops.isEmpty) return;
    final op = ops.removeLast();
    op.redo(currentSlice!.labels);
    (_undo[z] ??= []).add(op);
    proposal = null;
    _changed();
  }

  /// Puts the current slice back to the saved version. This is itself an edit, so it can be undone.
  void resetSlice() {
    final slice = currentSlice;
    if (slice == null) return;
    final op = EditOp.diff(slice.labels, _baseline[z]!);
    if (op == null) return;
    op.redo(slice.labels);
    _record(op);
  }

  /// Drops every unsaved edit.
  void discardAll() {
    for (final n in _dirty) {
      _slices[n]!.labels.setAll(0, _baseline[n]!);
    }
    _dirty.clear();
    _undo.clear();
    _redo.clear();
    _refined.clear();
    proposal = null;
    saveError = null;
    conflict = false;
    revision++;
    notifyListeners();
  }

  // -- saving -----------------------------------------------------------------------------------------------

  /// Uploads only the edited slices as a new version. On failure the edits stay on the device so the user can retry.
  Future<bool> save() async {
    final b = base;
    if (b == null || _dirty.isEmpty || saving) return false;
    saving = true;
    saveError = null;
    conflict = false;
    cancelStroke();
    notifyListeners();
    try {
      final edited = dirtySlices;
      final pngs = {
        for (final n in edited) n: await encodeLabelPng(_slices[n]!),
      };
      final saved = await repository.saveVersion(
        studyId,
        b.versionId,
        pngs,
        refined: [
          for (final n in edited)
            if (_refined.contains(n)) n,
        ],
      );
      // The saved slices are now the baseline; history starts again from here.
      for (final n in edited) {
        _baseline[n] = Uint8List.fromList(_slices[n]!.labels);
      }
      versions = [...versions, saved];
      base = saved;
      savedName = saved.name;
      _dirty.clear();
      _undo.clear();
      _redo.clear();
      _refined.clear();
      return true;
    } on ApiException catch (e) {
      if (e.code == 'VERSION_CONFLICT') {
        conflict = true;
      } else {
        saveError = e.message;
      }
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  // -- refinement -------------------------------------------------------------------------------------------

  void setRefineBand(double value) {
    refineBand = value;
    notifyListeners();
  }

  /// Asks the server to fit the current slice's edit to the image edge. Only produces a proposal.
  Future<void> refine() async {
    final slice = currentSlice;
    final b = base;
    if (slice == null || b == null || refining || !_dirty.contains(z)) return;
    final at = z;
    refining = true;
    refineError = null;
    proposal = null;
    notifyListeners();
    try {
      final result = await repository.refine(
        studyId,
        b.versionId,
        at,
        await encodeLabelPng(slice),
        label: label,
        bandWidth: refineBand.round(),
      );
      final proposed = await decodeLabelPng(result.png);
      if (at == z) {
        proposal = RefineProposal(at, proposed.labels, result.changedPixels);
      }
    } on ApiException catch (e) {
      refineError = e.message; // the user's edit is untouched
    } finally {
      refining = false;
      notifyListeners();
    }
  }

  /// Applies the proposal as one undoable edit.
  void acceptRefine() {
    final p = proposal;
    final slice = currentSlice;
    if (p == null || slice == null || p.slice != z) return;
    final op = EditOp.diff(slice.labels, p.labels);
    proposal = null;
    if (op == null) {
      notifyListeners();
      return;
    }
    op.redo(slice.labels);
    _refined.add(z);
    _record(op);
  }

  void rejectRefine() {
    proposal = null;
    notifyListeners();
  }

  @override
  void dispose() {
    strokeTick.dispose();
    super.dispose();
  }
}
