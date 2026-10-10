import 'package:flutter/material.dart';

ThemeData studioTheme() => ThemeData(
  scaffoldBackgroundColor: const Color(0xfff0f0f0),
  colorScheme: const ColorScheme.light(
    primary: Color(0xff242424),
    secondary: Color(0xff777777),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xfff8f8f8),
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffe8e8e8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffe8e8e8)),
    ),
  ),
);
