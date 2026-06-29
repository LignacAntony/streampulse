import 'package:flutter/material.dart';

import '../widgets/auth_tabs.dart';
import '../widgets/branded_header.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.initialTab});

  final AuthTab initialTab;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthTab _active = widget.initialTab;

  void _onTabChanged(AuthTab tab) {
    if (tab == _active) return;
    setState(() => _active = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 32,
                children: [
                  const BrandedHeader(),
                  AuthTabs(active: _active, onChanged: _onTabChanged),
                  _active == AuthTab.login
                      ? const LoginView(key: ValueKey('login'))
                      : RegisterView(
                          key: const ValueKey('register'),
                          onRegistered: () => _onTabChanged(AuthTab.login),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
