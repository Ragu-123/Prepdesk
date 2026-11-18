import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const googleBlue = Color(0xFF315DA8);
const googleBlueContainer = Color(0xFFDCE7FD);
const googleOnBlueContainer = Color(0xFF15335F);
const googleSurface = Colors.white;
const googleBackground = Color(0xFFF7F8FC);
const googleTextPrimary = Color(0xFF202630);
const googleTextSecondary = Color(0xFF58616E);
const googleBorder = Color(0xFFE0E2EC);
const googleHairline = Color(0xFFEDEFF5);
const severityHigh = Color(0xFFB3261E);
const severityMed = Color(0xFFE37400);
const severityLow = Color(0xFF315DA8);
const googleRed = Color(0xFFB3261E);
const googleAmber = Color(0xFFF29900);
const googleGreen = Color(0xFF137333);

final lightTheme = buildLightTheme(googleBlue);

/// One light color system for controls, forms, pickers and navigation.
ThemeData buildLightTheme(Color accent) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light).copyWith(
    primary: accent, onPrimary: Colors.white, surface: googleSurface,
    onSurface: googleTextPrimary, outline: const Color(0xFF747775), outlineVariant: googleBorder);
  return ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  fontFamily: 'NotoSans',
  splashFactory: InkSparkle.splashFactory,
  visualDensity: VisualDensity.standard,
  colorScheme: scheme,
  scaffoldBackgroundColor: googleBackground,
  cardColor: googleSurface,
  dividerColor: googleBorder,
  appBarTheme: const AppBarTheme(
    backgroundColor: googleBackground,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: googleTextPrimary),
    titleTextStyle: TextStyle(
      fontFamily: 'NotoSans',
      color: googleTextPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: googleSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
    ),
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(fontSize: 32, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -1),
    headlineMedium: TextStyle(fontSize: 28, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.7),
    titleLarge: TextStyle(fontSize: 22, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ).apply(bodyColor: googleTextPrimary, displayColor: googleTextPrimary),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 2)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
    elevation: 0, minimumSize: const Size(48, 48),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  )),
  outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
    minimumSize: const Size(48, 48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  )),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
    minimumSize: const Size(48, 48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)))),
  textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
    minimumSize: const Size(48, 48), foregroundColor: scheme.primary)),
  progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary,
    linearTrackColor: scheme.primaryContainer, circularTrackColor: scheme.surfaceContainerHighest),
  textSelectionTheme: TextSelectionThemeData(cursorColor: scheme.primary,
    selectionColor: scheme.primary.withValues(alpha: 0.2), selectionHandleColor: scheme.primary),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    elevation: 0,
    backgroundColor: scheme.primaryContainer,
    foregroundColor: scheme.onPrimaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    iconColor: googleTextSecondary,
    minVerticalPadding: 12,
  ),
  pageTransitionsTheme: const PageTransitionsTheme(builders: {
    TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  }),

  );
}

const systemUiOverlayStyleLight = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarDividerColor: Colors.transparent,
);
