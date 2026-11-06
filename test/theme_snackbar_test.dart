import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/core/theme/app_theme.dart';

void main() {
  group('SnackBar Theme Light/Dark Mode Adaptation Tests', () {
    testWidgets('Dark theme configures elevated floating SnackBar with white text and border', (tester) async {
      final darkTheme = AppTheme.darkTheme();
      final snackTheme = darkTheme.snackBarTheme;

      expect(snackTheme.behavior, equals(SnackBarBehavior.floating));
      expect(snackTheme.backgroundColor, equals(AppColors.darkSurfaceElevated));
      expect(snackTheme.contentTextStyle?.color, equals(AppColors.darkTextPrimary));
      expect(snackTheme.shape, isA<RoundedRectangleBorder>());

      final shape = snackTheme.shape as RoundedRectangleBorder;
      expect(shape.side.color, equals(AppColors.darkBorder));
      expect(shape.borderRadius, equals(BorderRadius.circular(14)));
    });

    testWidgets('Light theme configures crisp surface floating SnackBar with dark text and border', (tester) async {
      final lightTheme = AppTheme.lightTheme();
      final lightSnackTheme = lightTheme.snackBarTheme;

      expect(lightSnackTheme.behavior, equals(SnackBarBehavior.floating));
      expect(lightSnackTheme.backgroundColor, equals(AppColors.lightSurface));
      expect(lightSnackTheme.contentTextStyle?.color, equals(AppColors.lightTextPrimary));
      expect(lightSnackTheme.shape, isA<RoundedRectangleBorder>());

      final shape = lightSnackTheme.shape as RoundedRectangleBorder;
      expect(shape.side.color, equals(AppColors.lightBorder));
      expect(shape.borderRadius, equals(BorderRadius.circular(14)));
    });
  });
}
