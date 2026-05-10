import 'package:flutter/material.dart';

class LoginFormObject {
  final email = TextEditingController();
  final password = TextEditingController();

  bool obscurePassword = true;

  void dispose() {
    email.dispose();
    password.dispose();
  }
}
