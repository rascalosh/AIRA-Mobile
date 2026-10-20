import 'package:aira_mobile/core/design_system/status_chip.dart';
import 'package:aira_mobile/data/models/study.dart';
import 'package:aira_mobile/features/studies/presentation/study_format.dart';
import 'package:flutter_test/flutter_test.dart';

NiftiFile _nifti(MriModality m) => NiftiFile(
  resourceId: 'r-${m.apiValue}',
  seriesId: 's',
  modality: m,
  shape: const [64, 64, 24],
  voxelSpacing: const [1, 1, 3],
);

Study _study(List<MriModality> modalities, {SegmentationInfo? segmentation}) =>
    Study(
      studyId: 'abc',
      status: StudyStatus.converted,
      modalities: modalities,
      niftiFiles: [for (final m in modalities) _nifti(m)],
      segmentation: segmentation,
    );

void main() {
  sliceTests();
  const seg = SegmentationInfo(
    resourceId: 'mask',
    label: 'Lesion',
    volumeMl: 3.2,
    modelName: 'model',
    modelNote: 'Experimental',
  );

  test('the model needs T2W, ADC and DWI', () {
    final t2Only = _study([MriModality.t2w]);
    expect(missingForModel(t2Only), [MriModality.adc, MriModality.dwi]);
    expect(canSegment(t2Only), isFalse);
    expect(chipStatusFor(t2Only), ChipStatus.missing);
    expect(needsAction(t2Only), isTrue);

    final all = _study([MriModality.t2w, MriModality.adc, MriModality.dwi]);
    expect(canSegment(all), isTrue);
    expect(chipStatusFor(all), ChipStatus.ready);
  });

  test('a segmented study is completed and still counts as ready', () {
    final done = _study([
      MriModality.t2w,
      MriModality.adc,
      MriModality.dwi,
    ], segmentation: seg);
    expect(chipStatusFor(done), ChipStatus.completed);
    expect(isReady(done), isTrue);
  });

  test('parses the segmentation block and keeps it through copyWith', () {
    final study = Study.fromJson({
      'study_id': 'abc',
      'status': 'converted',
      'segmentation': {
        'resource_id': 'mask',
        'label': 'Lesion',
        'volume_ml': 3,
        'model_name': 'm',
        'model_note': 'Experimental',
      },
    });
    expect(study.segmentation?.volumeMl, 3.0);
    expect(
      study.copyWith(status: StudyStatus.converted).segmentation?.label,
      'Lesion',
    );
    expect(
      Study.fromJson({'study_id': 'x', 'status': 'converted'}).segmentation,
      isNull,
    );
  });
}

void sliceTests() {
  test('slices are shown 1-based, grouped into ranges', () {
    expect(formatSlices(const []), '');
    expect(formatSlices(const [5]), '6');
    expect(formatSlices(const [5, 6]), '6–7');
    expect(formatSlices(const [11, 5, 6, 7, 20]), '6–8, 12, 21');
  });

  test('the segmentation parses which slices contain mask', () {
    final seg = SegmentationInfo.fromJson({
      'resource_id': 'm',
      'label': 'Lesion',
      'volume_ml': 0.1,
      'model_name': 'x',
      'model_note': 'n',
      'slices_with_mask': [5, 6],
    });
    expect(seg.slicesWithMask, [5, 6]);
    // Older servers do not send the field.
    expect(
      SegmentationInfo.fromJson({
        'resource_id': 'm',
        'label': 'L',
        'volume_ml': 0,
        'model_name': '',
        'model_note': '',
      }).slicesWithMask,
      isEmpty,
    );
  });
}
