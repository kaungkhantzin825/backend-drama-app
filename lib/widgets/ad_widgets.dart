import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/theme.dart';
import '../services/ad_service.dart';

/// A 320×50 banner that manages its own load/dispose cycle.
///
/// Renders nothing at all when ads are unsupported (web, desktop) or the fill
/// fails, so a screen can drop it in unconditionally without leaving a gap.
class BannerAdBar extends StatefulWidget {
  const BannerAdBar({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  State<BannerAdBar> createState() => _BannerAdBarState();
}

class _BannerAdBarState extends State<BannerAdBar> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Waits (briefly) for the remote config so a backend "ads off" or a new
  /// banner waterfall applies from the first banner.
  Future<void> _start() async {
    await AdService.instance.ready
        .timeout(const Duration(seconds: 4), onTimeout: () {});
    if (mounted) _loadTier(0);
  }

  /// Loads banner waterfall step [tier]; a no-fill falls through to the next.
  void _loadTier(int tier) {
    final ad = AdService.instance.createBanner(
      tier: tier,
      onLoaded: () {
        if (mounted) setState(() => _loaded = true);
      },
      onFailed: () {
        // The service already disposed the failed ad.
        _ad = null;
        if (!mounted) return;
        setState(() => _loaded = false);
        _loadTier(tier + 1);
      },
    );

    if (ad == null) return;

    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;

    if (ad == null || !_loaded) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: Center(
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}

/// A native ad rendered with the SDK's built-in medium template.
///
/// Collapses to nothing while it loads and when no fill arrives, which matters
/// here because it sits inside a scrolling feed.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();

    final ad = AdService.instance.createNativeAd(
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );

    if (ad == null) return;

    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;

    if (ad == null || !_loaded) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sponsored',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: double.infinity,
              height: 300,
              child: AdWidget(ad: ad),
            ),
          ),
        ],
      ),
    );
  }
}
