import 'package:flutter/material.dart';

import 'core/state/display_controller.dart';
import 'ui/screens/ambient_screen.dart';
import 'ui/strings.dart';
import 'ui/theme/app_theme.dart';

class HermesApp extends StatelessWidget {
  const HermesApp({super.key, required this.controller});

  final DisplayController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: AmbientScreen(controller: controller),
    );
  }
}
