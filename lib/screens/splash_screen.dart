import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The first thing the app shows while the session bootstraps.
///
/// Brand mark, a subtle pulse, and no layout shift when the shell replaces it.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.message, this.onRetry});

  /// When set, the splash becomes an error state with a retry action.
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = message != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                'DramaLoop',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Short dramas. Real rewards.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 34),
              if (!failed)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else ...[
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 180,
                  child: FilledButton(
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
