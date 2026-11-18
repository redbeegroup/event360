library event360_ui;

import 'package:flutter/material.dart';

class Event360Theme {
  static const Color brand = Color(0xFF6C2BD9);

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        // TODO: bundle Noto Sans Myanmar / Pyidaungsu as asset font for Myanmar Unicode.
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark),
      );
}
