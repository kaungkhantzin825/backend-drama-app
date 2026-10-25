import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/client_context.dart';
import '../core/theme.dart';
import '../models/remote_config.dart';
import '../widgets/common.dart';

/// Full-screen gates driven by the backend's release policy.
///
/// Both take over the whole app (the MaterialApp's `home`), so nothing behind
/// them can make API calls that would only fail with 426 / 503.

/// Shown while the backend is in maintenance mode.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _GateScaffold(
      icon: Icons.build_circle_rounded,
      title: 'Down for maintenance',
      message: message.isEmpty ? 'We will be back shortly.' : message,
      action: FilledButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}

/// Shown when this build is older than `app_version.min_supported`.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.release});

  final ReleasePolicy release;

  @override
  Widget build(BuildContext context) {
    return _GateScaffold(
      icon: Icons.system_update_rounded,
      title: 'Update required',
      message: '${release.updateMessage.isEmpty ? 'This version of DramaLoop is no longer supported.' : release.updateMessage}\n\n'
          'You have ${ClientContext.appVersion}; version ${release.minSupported} or newer is needed.',
      action: FilledButton(
        onPressed: release.updateUrl.isEmpty ? null : () => openStore(context, release.updateUrl),
        child: const Text('Update now'),
      ),
    );
  }
}

/// The optional "new version available" prompt, shown once per launch.
Future<void> showOptionalUpdateDialog(BuildContext context, ReleasePolicy release) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Update available'),
      content: Text(
        '${release.updateMessage.isEmpty ? 'A new version of DramaLoop is available.' : release.updateMessage}\n\n'
        'Version ${release.latest} — you have ${ClientContext.appVersion}.',
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        if (release.updateUrl.isNotEmpty)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              openStore(context, release.updateUrl);
            },
            child: const Text('Update'),
          ),
      ],
    ),
  );
}

Future<void> openStore(BuildContext context, String url) async {
  final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
      .catchError((_) => false);

  if (!opened && context.mounted) {
    showSnack(context, 'Could not open the store.', error: true);
  }
}

class _GateScaffold extends StatelessWidget {
  const _GateScaffold({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: AppTheme.accent),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 28),
                SizedBox(width: 200, child: action),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
