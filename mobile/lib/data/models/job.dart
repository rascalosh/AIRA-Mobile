import 'study.dart';

enum JobStatus {
  queued,
  running,
  completed,
  failed;

  static JobStatus fromApi(String? value) => JobStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => JobStatus.failed,
      );
}

/// A server-side segmentation job. Poll until [isDone].
class SegmentationJob {
  const SegmentationJob({
    required this.jobId,
    required this.studyId,
    required this.status,
    this.errorMessage,
    this.segmentation,
  });

  final String jobId;
  final String studyId;
  final JobStatus status;

  /// User-safe failure message, set when [status] is [JobStatus.failed].
  final String? errorMessage;

  /// The result, set when [status] is [JobStatus.completed].
  final SegmentationInfo? segmentation;

  bool get isDone => status == JobStatus.completed || status == JobStatus.failed;

  factory SegmentationJob.fromJson(Map<String, dynamic> json) => SegmentationJob(
        jobId: json['job_id'] as String,
        studyId: json['study_id'] as String,
        status: JobStatus.fromApi(json['status'] as String?),
        errorMessage: (json['error'] as Map<String, dynamic>?)?['message'] as String?,
        segmentation: json['segmentation'] == null
            ? null
            : SegmentationInfo.fromJson(json['segmentation'] as Map<String, dynamic>),
      );
}
