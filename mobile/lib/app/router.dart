import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/annotation/presentation/compare_screen.dart';
import '../features/annotation/presentation/mask_editor_screen.dart';
import '../features/exports/presentation/exports_screen.dart';
import '../features/export/presentation/export_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/results/presentation/results_screen.dart';
import '../features/segmentation/presentation/segmentation_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/studies/presentation/studies_screen.dart';
import '../features/studies/presentation/study_detail_screen.dart';
import '../features/study_import/presentation/study_import_screen.dart';
import '../features/viewer/presentation/viewer_screen.dart';
import 'app_shell.dart';

class Routes {
  Routes._();

  static const home = '/';
  static const studies = '/studies';
  static const exports = '/exports';
  static const settings = '/settings';
  static const importStudy = '/import';
  static String study(String studyId) => '/studies/$studyId';
  static String viewer(String studyId) => '/studies/$studyId/viewer';
  static String segmentation(String studyId) =>
      '/studies/$studyId/segmentation';
  static String edit(String studyId) => '/studies/$studyId/edit';
  static String compare(String studyId) => '/studies/$studyId/compare';
  static String results(String studyId) => '/studies/$studyId/results';
  static String export(String studyId) => '/studies/$studyId/export';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.studies,
                builder: (_, _) => const StudiesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.exports,
                builder: (_, _) => const ExportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.importStudy,
        builder: (_, _) => const StudyImportScreen(),
      ),
      GoRoute(
        path: '/studies/:studyId',
        builder: (_, state) =>
            StudyDetailScreen(studyId: state.pathParameters['studyId']!),
      ),
      GoRoute(
        path: '/studies/:studyId/viewer',
        builder: (_, state) =>
            ViewerScreen(studyId: state.pathParameters['studyId']!),
      ),
      GoRoute(
        path: '/studies/:studyId/edit',
        builder: (_, state) =>
            MaskEditorScreen(studyId: state.pathParameters['studyId']!),
      ),
      GoRoute(
        path: '/studies/:studyId/compare',
        builder: (_, state) =>
            CompareScreen(studyId: state.pathParameters['studyId']!),
      ),
      GoRoute(
        path: '/studies/:studyId/segmentation',
        builder: (_, state) =>
            SegmentationScreen(studyId: state.pathParameters['studyId']!),
      ),
      GoRoute(
        path: '/studies/:studyId/results',
        builder: (_, state) =>
            ResultsScreen(studyId: state.pathParameters['studyId']!),
      ),
      GoRoute(
        path: '/studies/:studyId/export',
        builder: (_, state) =>
            ExportScreen(studyId: state.pathParameters['studyId']!),
      ),
    ],
  );
});
