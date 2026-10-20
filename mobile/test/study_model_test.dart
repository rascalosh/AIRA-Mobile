import 'package:aira_mobile/data/models/study.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an upload response', () {
    final study = Study.fromJson({
      'study_id': 'abc123',
      'status': 'uploaded',
      'modalities': ['T2W', 'ADC'],
      'series': [
        {
          'series_id': 's1',
          'modality': 'T2W',
          'num_instances': 24,
          'description': 't2_tse_tra',
        },
        {
          'series_id': 's2',
          'modality': 'unknown',
          'num_instances': 10,
          'description': null,
        },
      ],
      'skipped_files': 2,
    });

    expect(study.status, StudyStatus.uploaded);
    expect(study.modalities, [MriModality.t2w, MriModality.adc]);
    expect(study.series.first.numInstances, 24);
    expect(study.series.last.modality, MriModality.unknown);
    expect(study.skippedFiles, 2);
    expect(study.isConverted, isFalse);
  });

  test('parses a convert response and merges it', () {
    const uploaded = Study(
      studyId: 'abc123',
      status: StudyStatus.uploaded,
      modalities: [MriModality.t2w],
    );
    final converted = Study.fromJson({
      'study_id': 'abc123',
      'status': 'converted',
      'nifti_files': [
        {
          'modality': 'T2W',
          'series_id': 's1',
          'resource_id': 'r1',
          'shape': [320, 320, 24],
          'voxel_spacing': [0.5, 0.5, 3.0],
        },
      ],
    });

    final merged = uploaded.copyWith(
      status: converted.status,
      niftiFiles: converted.niftiFiles,
    );
    expect(merged.isConverted, isTrue);
    expect(merged.modalities, [MriModality.t2w]);
    expect(merged.niftiFiles.single.shape, [320, 320, 24]);
    expect(merged.niftiFiles.single.voxelSpacing.last, 3.0);
  });

  test('unknown values fall back safely', () {
    expect(MriModality.fromApi('FLAIR'), MriModality.unknown);
    expect(StudyStatus.fromApi('weird'), StudyStatus.failed);
  });
}
