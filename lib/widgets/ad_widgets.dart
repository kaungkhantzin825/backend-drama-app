import 'package:applovin_max/applovin_max.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/ad_service.dart';

/// A MAX ad view (banner or MREC) that is preloaded first and only mounted
/// once it has actually filled, so an empty slot never takes up space.
///
/// Renders nothing on web/desktop, when ads are off, when the format has no
/// unit, or when nothing fills.
class _PreloadedAdView extends StatefulWidget {
  const _PreloadedAdView({
    required this.format,
    required this.placement,
    required this.builder,
  });

  final String format;
  final String placement;
  final Widget Function(BuildContext context, Widget adView) builder;

  @override
  State<_PreloadedAdView> createState() => _PreloadedAdViewState();
}

class _PreloadedAdViewState extends State<_PreloadedAdView> {
  AdViewId? _id;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    final id = await AdService.instance.preloadAdView(widget.format, placement: widget.placement);
    if (id == null) return;

    // The widget may have gone while the ad was loading.
    if (_disposed) {
      await AdService.instance.destroyAdView(id);
      return;
    }

    setState(() => _id = id);
  }

  @override
  void dispose() {
    _disposed = true;
    final id = _id;
    if (id != null) AdService.instance.destroyAdView(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    final unit = AdService.instance.unitFor(widget.format);
    if (id == null || unit == null) return const SizedBox.shrink();

    final service = AdService.instance;
    void track(String event, MaxAd ad) =>
        service.trackAdView(event, widget.format, ad, placement: widget.placement);

    return widget.builder(
      context,
      MaxAdView(
        adUnitId: unit,
        adFormat: widget.format == 'mrec' ? AdFormat.mrec : AdFormat.banner,
        adViewId: id,
        placement: widget.placement,
        listener: AdViewAdListener(
          onAdLoadedCallback: (_) {},
          onAdLoadFailedCallback: (_, __) {},
          onAdClickedCallback: (ad) => track('click', ad),
          onAdExpandedCallback: (_) {},
          onAdCollapsedCallback: (_) {},
          onAdRevenuePaidCallback: (ad) {
            // MAX reports revenue per impression, so this doubles as one.
            track('impression', ad);
            track('paid', ad);
          },
        ),
      ),
    );
  }
}

/// A 320×50 banner (adaptive width) that manages its own load/destroy cycle.
class BannerAdBar extends StatelessWidget {
  const BannerAdBar({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return _PreloadedAdView(
      format: 'banner',
      placement: 'tab_bar',
      builder: (context, adView) => Padding(
        padding: padding,
        child: SizedBox(width: double.infinity, child: adView),
      ),
    );
  }
}

/// A "Sponsored" 300×250 MREC card for the Home feed.
///
/// Collapses to nothing while it loads and when no fill arrives, which matters
/// here because it sits inside a scrolling feed.
class MrecAdCard extends StatelessWidget {
  const MrecAdCard({super.key, this.placement = 'home_feed'});

  final String placement;

  @override
  Widget build(BuildContext context) {
    return _PreloadedAdView(
      format: 'mrec',
      placement: placement,
      builder: (context, adView) => Padding(
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
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(width: 300, height: 250, child: adView),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
