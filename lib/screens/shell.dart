import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../services/ad_service.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'release_gate_screens.dart';
import 'wallet_screen.dart';

/// The signed-in app frame: four tabs over one persistent index.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  /// The optional-update prompt appears at most once per app launch.
  static bool _updatePromptShown = false;

  // Kept alive so switching tabs does not refetch the feed or lose scroll.
  static const _screens = <Widget>[
    HomeScreen(),
    BrowseScreen(),
    WalletScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();

    // The app-open ad belongs on the first frame of the signed-in shell, not
    // over the splash — there is nothing to come back to before that.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AdService.instance.maybeShowAppOpen();
      // After the app-open ad, never on top of it.
      if (mounted) await _maybePromptUpdate();
    });
  }

  Future<void> _maybePromptUpdate() async {
    if (_updatePromptShown) return;

    final config = await ref.read(remoteConfigProvider.future);
    if (!mounted || !config.release.updateAvailable) return;

    _updatePromptShown = true;
    await showOptionalUpdateDialog(context, config.release);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A banner sits above the tab bar so it is visible on every tab.
          const ColoredBox(
            color: AppTheme.background,
            child: BannerAdBar(padding: EdgeInsets.only(bottom: 4)),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.divider)),
            ),
            child: BottomNavigationBar(
              currentIndex: _index,
              onTap: (value) => setState(() => _index = value),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_rounded),
                  activeIcon: Icon(Icons.search_rounded),
                  label: 'Browse',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bolt_outlined),
                  activeIcon: Icon(Icons.bolt_rounded),
                  label: 'Rewards',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded),
                  activeIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
