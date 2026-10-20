import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'app/theme.dart';

void main() {
  AppConfig.assertSecure();

  // Failsafe: replace Flutter's default red "crash" screen with a calm,
  // on-brand message wherever a widget fails to build, instead of a wall of
  // stack-trace text — this is a clinical app, and raw errors are neither
  // useful nor reassuring to someone reviewing a scan. The underlying error
  // is still logged to the debug console via FlutterError.presentError.
  ErrorWidget.builder = (details) {
    FlutterError.presentError(details);
    return const _CrashFailsafe();
  };

  // Catch anything that escapes the widget-build path too (a framework
  // assertion during a frame callback, an unhandled async error) so it's
  // logged rather than silently terminating the isolate.
  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    return true;
  };

  runApp(const ProviderScope(child: AiraApp()));
}

class _CrashFailsafe extends StatelessWidget {
  const _CrashFailsafe();

  @override
  Widget build(BuildContext context) {
    // Deliberately theme-independent: this can render above a broken tree.
    const c = AiraColors.standard;
    return Container(
      width: double.infinity,
      color: c.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleAlert, size: 40, color: c.dangerFg),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: c.textTitle,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This screen ran into a problem. Go back and try again. '
            'Nothing on the server is affected.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: c.textSecondary,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
