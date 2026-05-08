import 'package:flutter/material.dart';

import '../utils/register_validators.dart';

class RegisterFormObject {
  final username = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool acceptedTerms = false;

  String? validateConfirm(String? value) =>
      RegisterValidators.confirmPassword(value, password.text);

  void dispose() {
    username.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
  }
}
