/// Data models mirroring the image-processing API contract (backend `app/models/schemas.py`).
library;

enum MriModality {
  t2w('T2W', 'T2-weighted'),
  dwi('DWI', 'Diffusion'),
  adc('ADC', 'ADC map'),
  unknown('unknown', 'Unknown');

  const MriModality(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MriModality fromApi(String? value) => MriModality.values.firstWhere(
        (m) => m.apiValue == value,
        orElse: () => MriModality.unknown,
      );
}

enum StudyStatus {
  uploaded,
  converting,
  converted,
  failed;

  static StudyStatus fromApi(String? value) => StudyStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => StudyStatus.failed,
      );
}

class SeriesInfo {
  const SeriesInfo({
    required this.seriesId,
    required this.modality,
    required this.numInstances,
    this.description,
  });

  final String seriesId;
  final MriModality modality;
  final int numInstances;
  final String? description;

  factory SeriesInfo.fromJson(Map<String, dynamic> json) => SeriesInfo(
        seriesId: json['series_id'] as String,
        modality: MriModality.fromApi(json['modality'] as String?),
        numInstances: (json['num_instances'] as num).toInt(),
        description: json['description'] as String?,
      );
}

class NiftiFile {
  const NiftiFile({
    required this.resourceId,
    required this.seriesId,
    required this.modality,
    required this.shape,
    required this.voxelSpacing,
  });

  final String resourceId;
  final String seriesId;
  final MriModality modality;
  final List<int> shape;
  final List<double> voxelSpacing;

  factory NiftiFile.fromJson(Map<String, dynamic> json) => NiftiFile(
        resourceId: json['resource_id'] as String,
        seriesId: json['series_id'] as String,
        modality: MriModality.fromApi(json['modality'] as String?),
        shape: [for (final d in json['shape'] as List) (d as num).toInt()],
        voxelSpacing: [for (final d in json['voxel_spacing'] as List) (d as num).toDouble()],
      );
}

class Study {
  const Study({
    required this.studyId,
    required this.status,
    this.modalities = const [],
    this.series = const [],
    this.niftiFiles = const [],
    this.skippedFiles = 0,
    this.createdAt,
  });

  final String studyId;
  final StudyStatus status;
  final List<MriModality> modalities;
  final List<SeriesInfo> series;
  final List<NiftiFile> niftiFiles;
  final int skippedFiles;
  final DateTime? createdAt;

  bool get isConverted => status == StudyStatus.converted;

  /// Parses upload, convert and get-study responses, which share field names.
  factory Study.fromJson(Map<String, dynamic> json) => Study(
        studyId: json['study_id'] as String,
        status: StudyStatus.fromApi(json['status'] as String?),
        modalities: [
          for (final m in (json['modalities'] as List?) ?? const []) MriModality.fromApi(m as String?),
        ],
        series: [
          for (final s in (json['series'] as List?) ?? const []) SeriesInfo.fromJson(s as Map<String, dynamic>),
        ],
        niftiFiles: [
          for (final n in (json['nifti_files'] as List?) ?? const []) NiftiFile.fromJson(n as Map<String, dynamic>),
        ],
        skippedFiles: (json['skipped_files'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] == null ? null : DateTime.tryParse(json['created_at'] as String),
      );

  /// Merges a partial response (e.g. convert) into the known study.
  Study copyWith({
    StudyStatus? status,
    List<MriModality>? modalities,
    List<SeriesInfo>? series,
    List<NiftiFile>? niftiFiles,
  }) =>
      Study(
        studyId: studyId,
        status: status ?? this.status,
        modalities: modalities ?? this.modalities,
        series: series ?? this.series,
        niftiFiles: niftiFiles ?? this.niftiFiles,
        skippedFiles: skippedFiles,
        createdAt: createdAt,
      );
}
