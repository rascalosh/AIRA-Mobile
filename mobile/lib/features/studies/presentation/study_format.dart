import '../../../core/design_system/status_chip.dart';
import '../../../data/models/study.dart';

/// Display helpers shared by Home, Studies and Study detail.

String studyLabel(Study s) => 'Study ${s.studyId.length > 8 ? s.studyId.substring(0, 8) : s.studyId}';

String modalitiesText(Study s) {
  final names = {for (final m in s.modalities) m.apiValue}.toList();
  return names.isEmpty ? 'No modalities detected' : names.join(', ');
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "24 Sep 2026", or null when the study has no timestamp.
String? formatDate(DateTime? d) {
  if (d == null) return null;
  final local = d.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Slices along the last spatial axis of the largest converted volume.
int sliceCount(Study s) {
  var max = 0;
  for (final n in s.niftiFiles) {
    if (n.shape.length >= 3 && n.shape[2] > max) max = n.shape[2];
  }
  return max;
}

/// The model needs T2W; a converted study without it cannot be segmented.
bool isMissingT2w(Study s) => s.isConverted && !s.modalities.contains(MriModality.t2w);

ChipStatus chipStatusFor(Study s) {
  if (s.status == StudyStatus.failed) return ChipStatus.failed;
  if (s.status == StudyStatus.converting) return ChipStatus.processing;
  if (s.status == StudyStatus.uploaded) return ChipStatus.draft;
  return isMissingT2w(s) ? ChipStatus.missing : ChipStatus.ready;
}

/// Studies that cannot move forward without the user doing something.
bool needsAction(Study s) {
  final status = chipStatusFor(s);
  return status == ChipStatus.failed || status == ChipStatus.missing || status == ChipStatus.draft;
}

String studyMetaLine(Study s) {
  final parts = [
    formatDate(s.createdAt),
    if (sliceCount(s) > 0) '${sliceCount(s)} slices',
  ].whereType<String>();
  return parts.join(' · ');
}
