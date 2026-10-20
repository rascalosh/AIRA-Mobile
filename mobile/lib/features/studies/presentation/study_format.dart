import '../../../core/design_system/status_chip.dart';
import '../../../data/models/study.dart';

/// Display helpers shared by Home, Studies and Study detail.

String studyLabel(Study s) =>
    'Study ${s.studyId.length > 8 ? s.studyId.substring(0, 8) : s.studyId}';

String modalitiesText(Study s) {
  final names = {for (final m in s.modalities) m.apiValue}.toList();
  return names.isEmpty ? 'No modalities detected' : names.join(', ');
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

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

/// The bundled model takes all three sequences.
const modelInputs = [MriModality.t2w, MriModality.adc, MriModality.dwi];

/// Model inputs a converted study does not have (empty until the study is converted).
List<MriModality> missingForModel(Study s) {
  if (!s.isConverted) return const [];
  final have = {for (final n in s.niftiFiles) n.modality};
  return [
    for (final m in modelInputs)
      if (!have.contains(m)) m,
  ];
}

bool canSegment(Study s) => s.isConverted && missingForModel(s).isEmpty;

/// Converted with every model input, whether or not it has been segmented yet.
bool isReady(Study s) {
  final status = chipStatusFor(s);
  return status == ChipStatus.ready || status == ChipStatus.completed;
}

ChipStatus chipStatusFor(Study s) {
  if (s.status == StudyStatus.failed) return ChipStatus.failed;
  if (s.status == StudyStatus.converting) return ChipStatus.processing;
  if (s.status == StudyStatus.uploaded) return ChipStatus.draft;
  if (s.segmentation != null) return ChipStatus.completed;
  return missingForModel(s).isNotEmpty ? ChipStatus.missing : ChipStatus.ready;
}

/// Studies that cannot move forward without the user doing something.
bool needsAction(Study s) {
  final status = chipStatusFor(s);
  return status == ChipStatus.failed ||
      status == ChipStatus.missing ||
      status == ChipStatus.draft;
}

/// 0-based slice indexes as 1-based ranges: `[5, 6, 11]` becomes `6–7, 12`.
String formatSlices(List<int> zeroBased) {
  final sorted = [...zeroBased]..sort();
  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    parts.add(
      i == j ? '${sorted[i] + 1}' : '${sorted[i] + 1}–${sorted[j] + 1}',
    );
    i = j + 1;
  }
  return parts.join(', ');
}

String studyMetaLine(Study s) {
  final parts = [
    formatDate(s.createdAt),
    if (sliceCount(s) > 0) '${sliceCount(s)} slices',
  ].whereType<String>();
  return parts.join(' · ');
}
