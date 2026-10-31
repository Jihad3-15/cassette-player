import 'package:flutter/material.dart';

/// Shows [message] in a SnackBar, replacing any SnackBar already visible.
void showSnack(ScaffoldMessengerState? messenger, String message) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs [action] and reports any error in a SnackBar instead of throwing.
///
/// The messenger is captured before the first await, so the caller's
/// BuildContext is never used across an async gap.
Future<void> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String errorMessage = 'Something went wrong',
  String? successMessage,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (successMessage != null) showSnack(messenger, successMessage);
  } catch (e) {
    showSnack(messenger, '$errorMessage: $e');
  }
}
