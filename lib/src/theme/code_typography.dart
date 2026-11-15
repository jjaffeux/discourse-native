import 'package:flutter/material.dart';

const String monospaceFontFamily = 'JetBrains Mono';

const List<String> monospaceFallback = [
  'packages/discourse_native/JetBrains Mono',
  'Consolas',
  'Monaco',
  'monospace',
];

const List<FontFeature> monospaceFontFeatures = [
  FontFeature.disable('liga'),
  FontFeature.disable('clig'),
  FontFeature.disable('dlig'),
  FontFeature.disable('hlig'),
  FontFeature.disable('calt'),
];

const TextStyle monospaceTextStyle = TextStyle(
  fontFamily: monospaceFontFamily,
  fontFamilyFallback: monospaceFallback,
  fontFeatures: monospaceFontFeatures,
);
