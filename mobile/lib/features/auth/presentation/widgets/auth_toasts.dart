import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

void showAuthSuccessToast(BuildContext context, String message) {
  _showAuthToast(context, message: message, type: ToastificationType.success);
}

void showAuthErrorToast(BuildContext context, String message) {
  _showAuthToast(context, message: message, type: ToastificationType.error);
}

void showAuthInfoToast(BuildContext context, String message) {
  _showAuthToast(context, message: message, type: ToastificationType.info);
}

void _showAuthToast(
  BuildContext context, {
  required String message,
  required ToastificationType type,
}) {
  toastification.dismissAll(delayForAnimation: false);
  toastification.show(
    context: context,
    type: type,
    style: ToastificationStyle.flatColored,
    alignment: Alignment.topCenter,
    autoCloseDuration: const Duration(seconds: 4),
    title: Text(message),
    showProgressBar: false,
  );
}
