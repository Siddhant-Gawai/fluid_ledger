import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../main.dart';

/// Show a success snackbar (teal)
void showSuccessSnackBar(String message) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppTheme.secondary),
  );
}

/// Show an error snackbar (red)
void showErrorSnackBar(String message) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppTheme.error),
  );
}

/// Show an info snackbar (indigo)
void showInfoSnackBar(String message, {Duration? duration}) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AppTheme.primary,
      duration: duration ?? const Duration(seconds: 3),
    ),
  );
}

/// Generic snackbar
void showAppSnackBar(String message, {Color? backgroundColor, Duration? duration}) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: duration ?? const Duration(seconds: 3),
    ),
  );
}