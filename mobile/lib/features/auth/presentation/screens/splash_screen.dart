import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/secure_storage.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    await Future.delayed(AppConstants.splashDuration);
    if (!mounted) return;

    final token = await SecureStorage().getAccessToken();
    if (!mounted) return;

    context.go(token != null ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        label: 'StreamPulse chargement',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 24,
            children: [
              // Zone tactile ≥ 44dp — WCAG 2.1 AA
              ConstrainedBox(
                constraints: const BoxConstraints.tightFor(
                  width: AppConstants.minTouchTarget * 2,
                  height: AppConstants.minTouchTarget * 2,
                ),
                child: Icon(
                  Icons.radio,
                  size: AppConstants.minTouchTarget * 1.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Column(
                spacing: 48,
                children: [
                  Text(
                    'StreamPulse',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
