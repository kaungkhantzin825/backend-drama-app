import 'package:flutter/material.dart';

import '../core/ad_config.dart';
import '../core/client_context.dart';
import '../core/theme.dart';
import '../services/ad_service.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';

/// A bench for the AdMob integration.
///
/// Every format the app ships can be fired from here without hunting for the
/// screen that triggers it, and each button prints what the SDK reported. It is
/// the fastest way to confirm the App ID, the unit ids and the network are all
/// wired correctly on a real device.
///
/// Reachable from Profile → AdMob test bench. Hidden behind no flag on purpose:
/// it only renders test ads while [AdConfig.useTestAds] is true, and it is the
/// first thing to remove when the app goes to production.
class AdTestScreen extends StatefulWidget {
  const AdTestScreen({super.key});

  @override
  State<AdTestScreen> createState() => _AdTestScreenState();
}

class _AdTestScreenState extends State<AdTestScreen> {
  final List<String> _log = [];
  bool _busy = false;

  void _note(String line) {
    if (!mounted) return;

    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $line');
      if (_log.length > 12) _log.removeLast();
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;

    setState(() => _busy = true);
    _note('$label → requested');

    try {
      await action();
    } catch (error) {
      _note('$label → threw: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = AdService.instance;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('AdMob test bench')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _StatusCard(service: service),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Full screen formats'),
          _BenchTile(
            icon: Icons.smart_display_rounded,
            title: 'Rewarded video',
            subtitle: 'Earns points in the player and the wallet',
            onTap: _busy
                ? null
                : () => _run('Rewarded', () async {
                      final outcome = await service.showRewarded();
                      _note('Rewarded → ${outcome.name}');
                    }),
          ),
          _BenchTile(
            icon: Icons.fullscreen_rounded,
            title: 'Interstitial',
            subtitle: 'Shown between videos, frequency capped',
            onTap: _busy
                ? null
                : () => _run('Interstitial', () async {
                      final shown = await service.maybeShowInterstitial(force: true);
                      _note('Interstitial → ${shown ? 'shown' : 'no fill'}');
                    }),
          ),
          _BenchTile(
            icon: Icons.open_in_new_rounded,
            title: 'App open',
            subtitle: 'Shown once per session when the shell mounts',
            onTap: _busy
                ? null
                : () => _run('App open', () async {
                      final shown = await service.maybeShowAppOpen(force: true);
                      _note('App open → ${shown ? 'shown' : 'no fill'}');
                    }),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'In-page formats'),
          const _BannerPreview(),
          const SizedBox(height: 10),
          const _NativePreview(),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Event log'),
          if (_log.isEmpty)
            const Text(
              'Nothing yet. Fire a format above.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            )
          else
            ..._log.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.service});

  final AdService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AdConfig.isSupported
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                size: 18,
                color: AdConfig.isSupported ? AppTheme.success : AppTheme.gold,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AdConfig.isSupported
                      ? 'SDK supported on this platform'
                      : 'SDK unsupported — ads are disabled here',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Line(
            'Mode',
            AdConfig.useTestAds ? 'Google test units' : 'Live units',
          ),
          _Line(
            'Config',
            service.settings.isRemote
                ? 'remote v${service.settings.version}'
                : 'build-time fallback',
          ),
          _Line('Ads enabled', service.settings.enabled ? 'yes' : 'no (remote switch)'),
          _Line('Interstitial gap', '${service.settings.interval.inSeconds}s'),
          _Line(
            'Interstitials',
            '${service.interstitialsThisSession} session (max ${service.rules.interstitialMaxPerSession}) · '
                '${service.interstitialsToday} today (max ${service.rules.interstitialMaxPerDay})',
          ),
          _Line(
            'Rewarded today',
            '${service.rewardedToday} (max ${service.rules.rewardedMaxPerDay})',
          ),
          _Line('A/B group', ClientContext.abGroup ?? 'none'),
          _Line('Initialised', service.isInitialized ? 'yes' : 'no'),
          _Line('Rewarded cached', service.hasRewardedAd ? 'yes' : 'no'),
          _Line('Interstitial cached', service.hasInterstitial ? 'yes' : 'no'),
          _Line('App open cached', service.hasAppOpenAd ? 'yes' : 'no'),
          const SizedBox(height: 10),
          const Text(
            'App ID',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          Text(
            AdConfig.androidAppId,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Units',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          // Waterfalls in the order they are tried.
          for (final format in const ['banner', 'interstitial', 'rewarded'])
            for (final (i, unit) in service.settings.waterfall(format).indexed)
              _Line('${format[0].toUpperCase()}${format.substring(1)} #${i + 1}', unit, mono: true),
          _Line('Native', AdConfig.nativeAdUnitId, mono: true),
          _Line('App open', AdConfig.appOpenAdUnitId, mono: true),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: mono ? 10.5 : 11,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenchTile extends StatelessWidget {
  const _BenchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ListTile(
        onTap: onTap,
        enabled: onTap != null,
        leading: Icon(icon, size: 20, color: AppTheme.accent),
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
        ),
        trailing: const Icon(
          Icons.play_circle_outline_rounded,
          size: 20,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _BannerPreview extends StatelessWidget {
  const _BannerPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: const Column(
        children: [
          Text(
            'Banner · 320×50',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          SizedBox(height: 8),
          BannerAdBar(),
        ],
      ),
    );
  }
}

class _NativePreview extends StatelessWidget {
  const _NativePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: const Column(
        children: [
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Native advanced · medium template',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ),
          NativeAdCard(),
        ],
      ),
    );
  }
}
