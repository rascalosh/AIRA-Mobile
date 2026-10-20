import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class AiraApp extends ConsumerWidget {
  const AiraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: MaterialApp.router(
        title: 'AIRA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.standard(),
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}
