import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/home_screen.dart';
import 'services/project_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final store = ProjectStore(FileProjectStorage(
      Directory('${supportDir.path}${Platform.pathSeparator}projects')));
  await store.load();
  runApp(Ev3ControllerApp(store: store));
}

class Ev3ControllerApp extends StatelessWidget {
  const Ev3ControllerApp({super.key, required this.store});

  final ProjectStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrickLogic',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD01012)),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      home: HomeScreen(store: store),
    );
  }
}
