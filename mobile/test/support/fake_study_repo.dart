import 'package:aira_mobile/core/network/api_client.dart';
import 'package:aira_mobile/core/network/api_exception.dart';
import 'package:aira_mobile/data/models/study.dart';
import 'package:aira_mobile/data/repositories/study_repository.dart';
import 'package:dio/dio.dart';

/// Stands in for the server: the studies list comes from here, with no network.
class FakeStudyRepo extends StudyRepository {
  FakeStudyRepo(this.studies, {this.fail = false}) : super(ApiClient(Dio()));

  List<Study> studies;
  bool fail;
  int erased = 0;

  @override
  Future<List<Study>> listStudies() async {
    if (fail) {
      throw const ApiException('Unable to reach the processing server.');
    }
    return studies;
  }

  @override
  Future<void> deleteAllMyData() async {
    erased++;
    studies = [];
  }

  @override
  Future<Study> getStudy(String studyId) async =>
      studies.firstWhere((s) => s.studyId == studyId);
}

Study fakeStudy(String id, {bool segmented = false}) => Study(
  studyId: id,
  status: StudyStatus.converted,
  modalities: const [MriModality.t2w, MriModality.adc, MriModality.dwi],
  niftiFiles: [
    for (final m in [MriModality.t2w, MriModality.adc, MriModality.dwi])
      NiftiFile(
        resourceId: 'r-$id-${m.apiValue}',
        seriesId: 's',
        modality: m,
        shape: const [64, 64, 21],
        voxelSpacing: const [1, 1, 3],
      ),
  ],
  segmentation: segmented
      ? const SegmentationInfo(
          resourceId: 'mask',
          label: 'Lesion',
          volumeMl: 0.1,
          modelName: 'm',
          modelNote: 'Experimental',
          slicesWithMask: [5, 6],
        )
      : null,
);
