import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/app_auth_controller.dart';
import 'audio/background_music_controller.dart';
import 'rooms/room_state.dart';
import 'screens/achievements_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/hall_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/room_screen.dart';
import 'screens/shop_screen.dart';
import 'settings/app_settings_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';

class BackHomeApp extends StatefulWidget {
  const BackHomeApp({super.key});

  @override
  State<BackHomeApp> createState() => _BackHomeAppState();
}

class _BackHomeAppState extends State<BackHomeApp> {
  late final AppSettingsController _settingsController;
  late final BackgroundMusicController _musicController;
  late final AppAuthController _authController;
  late final bool _useOfflineAuth;

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController();
    _useOfflineAuth = Firebase.apps.isEmpty;
    _authController = _useOfflineAuth
        ? AppAuthController.offline()
        : AppAuthController();
    _musicController = BackgroundMusicController(
      settingsController: _settingsController,
    );
    unawaited(_initializeControllers());
  }

  @override
  void dispose() {
    unawaited(_musicController.shutdown());
    _authController.dispose();
    _settingsController.dispose();
    super.dispose();
  }

  Future<void> _initializeControllers() async {
    await _settingsController.load();
    await _musicController.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settingsController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Back Home',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(_settingsController.textScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _AuthGate(
            settingsController: _settingsController,
            musicController: _musicController,
            authController: _authController,
            bypassAuth: _useOfflineAuth,
          ),
        );
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({
    required this.settingsController,
    required this.musicController,
    required this.authController,
    this.bypassAuth = false,
  });

  final AppSettingsController settingsController;
  final BackgroundMusicController musicController;
  final AppAuthController authController;
  final bool bypassAuth;

  @override
  Widget build(BuildContext context) {
    if (bypassAuth) {
      return AppShell(
        settingsController: settingsController,
        musicController: musicController,
        authController: authController,
      );
    }

    return AnimatedBuilder(
      animation: authController,
      builder: (context, _) {
        return StreamBuilder<User?>(
          initialData: authController.currentUser,
          stream: authController.authStateChanges,
          builder: (context, snapshot) {
            if (snapshot.data != null &&
                !authController.hasLoadedPendingEmailPasswordSetup) {
              return const Scaffold(
                body: Stack(
                  children: [
                    AmbientBackground(showSideGlow: true),
                    Center(child: CircularProgressIndicator()),
                  ],
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Scaffold(
                body: Stack(
                  children: [
                    AmbientBackground(showSideGlow: true),
                    Center(child: CircularProgressIndicator()),
                  ],
                ),
              );
            }

            if (snapshot.data == null ||
                authController.needsEmailVerification ||
                authController.needsEmailPasswordSetup) {
              return LoginScreen(authController: authController);
            }

            return AppShell(
              settingsController: settingsController,
              musicController: musicController,
              authController: authController,
            );
          },
        );
      },
    );
  }
}

enum AppTab { home, room, hall, chat, profile }

class AppShell extends StatefulWidget {
  const AppShell({
    required this.settingsController,
    required this.musicController,
    required this.authController,
    super.key,
  });

  final AppSettingsController settingsController;
  final BackgroundMusicController musicController;
  final AppAuthController authController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<AppTab> _navigationTabs = [
    AppTab.room,
    AppTab.hall,
    AppTab.chat,
    AppTab.profile,
  ];

  final RoomEditorController _roomController = RoomEditorController();
  final Set<AppTab> _initializedTabs = <AppTab>{};
  AppTab _currentTab = AppTab.home;

  // Room chrome (the floating nav card + shop button) auto-hides after a short
  // hold. It fades IN fast so a reveal snaps to full opacity, stays for the hold
  // window, then fades OUT slowly. The hold must comfortably exceed the fade-in
  // so the card actually reaches full opacity and lingers before hiding again.
  static const Duration _roomChromeFadeIn = Duration(milliseconds: 320);
  static const Duration _roomChromeFadeOut = Duration(seconds: 2);
  static const Duration _roomChromeHold = Duration(seconds: 4);

  Timer? _roomChromeFadeTimer;
  Timer? _roomChromeInputTimer;
  bool _roomChromeVisible = true;
  bool _roomChromeInteractive = true;
  bool _roomInSubview = false;

  @override
  void dispose() {
    _roomChromeFadeTimer?.cancel();
    _roomChromeInputTimer?.cancel();
    _roomController.dispose();
    super.dispose();
  }

  void _selectTab(AppTab tab) {
    setState(() {
      _currentTab = tab;
      if (tab == AppTab.room) {
        _roomChromeVisible = true;
        _roomChromeInteractive = true;
      } else {
        _roomChromeFadeTimer?.cancel();
        _roomChromeInputTimer?.cancel();
        _roomChromeVisible = true;
        _roomChromeInteractive = true;
      }
      if (tab != AppTab.home) {
        _initializedTabs.add(tab);
      }
    });
    if (tab == AppTab.room) {
      _scheduleRoomChromeFade();
    }
  }

  void _scheduleRoomChromeFade() {
    _roomChromeFadeTimer?.cancel();
    _roomChromeInputTimer?.cancel();
    _roomChromeFadeTimer = Timer(_roomChromeHold, () {
      if (!mounted || _currentTab != AppTab.room) {
        return;
      }
      setState(() {
        _roomChromeVisible = false;
      });
      // Keep the card tappable until it has fully faded out.
      _roomChromeInputTimer = Timer(_roomChromeFadeOut, () {
        if (!mounted || _currentTab != AppTab.room) {
          return;
        }
        setState(() {
          _roomChromeInteractive = false;
        });
      });
    });
  }

  void _revealRoomChrome() {
    if (_currentTab != AppTab.room) {
      return;
    }
    setState(() {
      _roomChromeVisible = true;
      _roomChromeInteractive = true;
    });
    _scheduleRoomChromeFade();
  }

  void _handleRoomSubviewChanged(bool inSubview) {
    if (_roomInSubview == inSubview) {
      return;
    }
    if (!inSubview) {
      // Returning to the main room view leaves the nav bar hidden until the user
      // double-taps to bring it up — so drop any pending auto-hide and hide it.
      _roomChromeFadeTimer?.cancel();
      _roomChromeInputTimer?.cancel();
    }
    setState(() {
      _roomInSubview = inSubview;
      if (!inSubview) {
        _roomChromeVisible = false;
        _roomChromeInteractive = false;
      }
    });
  }

  Future<void> _openShop() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopScreen(controller: _roomController),
      ),
    );
  }

  Future<void> _openAchievements() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()));
  }

  Widget _buildHomePage() {
    return HomeScreen(
      authController: widget.authController,
      onOpenRoom: () => _selectTab(AppTab.room),
      onOpenHall: () => _selectTab(AppTab.hall),
      onOpenChat: () => _selectTab(AppTab.chat),
      onOpenShop: _openShop,
      onOpenAchievements: _openAchievements,
    );
  }

  Widget _buildTabPage(AppTab tab) {
    if (!_initializedTabs.contains(tab)) {
      return const SizedBox.shrink();
    }

    switch (tab) {
      case AppTab.room:
        return RoomScreen(
          key: const ValueKey(AppTab.room),
          controller: _roomController,
          settingsController: widget.settingsController,
          musicController: widget.musicController,
          onOpenShop: _openShop,
          isActive: _currentTab == AppTab.room,
          isChromeVisible: _roomChromeVisible,
          isChromeInteractive: _roomChromeInteractive,
          onRevealChrome: _revealRoomChrome,
          onSubviewChanged: _handleRoomSubviewChanged,
        );
      case AppTab.hall:
        return KeyedSubtree(
          key: const ValueKey(AppTab.hall),
          child: SafeArea(
            child: HallScreen(authController: widget.authController),
          ),
        );
      case AppTab.chat:
        return KeyedSubtree(
          key: const ValueKey(AppTab.chat),
          child: SafeArea(
            child: ChatScreen(authController: widget.authController),
          ),
        );
      case AppTab.profile:
        return KeyedSubtree(
          key: const ValueKey(AppTab.profile),
          child: SafeArea(
            child: ProfileScreen(
              settingsController: widget.settingsController,
              musicController: widget.musicController,
              authController: widget.authController,
            ),
          ),
        );
      case AppTab.home:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTabbedPages() {
    final currentIndex = _navigationTabs.indexOf(_currentTab);
    return IndexedStack(
      index: currentIndex < 0 ? 0 : currentIndex,
      children: _navigationTabs.map(_buildTabPage).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRoomTab = _currentTab == AppTab.room;
    // The nav bar only shows in the main room view — not in the desk/night
    // subviews — and otherwise follows the chrome auto-hide.
    final navShown = !isRoomTab || (_roomChromeVisible && !_roomInSubview);

    return Scaffold(
      backgroundColor: isRoomTab
          ? const Color(0xFF080706)
          : const Color.fromARGB(0, 212, 255, 18),
      body: _currentTab == AppTab.home
          ? Stack(
              children: [
                AmbientBackground(showSideGlow: false),
                SafeArea(bottom: false, child: _buildHomePage()),
              ],
            )
          : Stack(
              children: [
                if (!isRoomTab) const AmbientBackground(showSideGlow: true),
                // The content fills the whole screen and flows under the
                // floating nav card below.
                Positioned.fill(child: _buildTabbedPages()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring:
                        isRoomTab && (!_roomChromeInteractive || _roomInSubview),
                    child: AnimatedOpacity(
                      duration: isRoomTab
                          ? (navShown
                                ? _roomChromeFadeIn
                                // Snappy hide when entering a subview; gentle
                                // 2s fade for the idle auto-hide.
                                : (_roomInSubview
                                      ? _roomChromeFadeIn
                                      : _roomChromeFadeOut))
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeInOutCubic,
                      opacity: navShown ? 1 : 0,
                      child: _FloatingNavBar(
                        currentTab: _currentTab,
                        onSelect: _selectTab,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.currentTab, required this.onSelect});

  final AppTab currentTab;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              ),
              // NavigationBar wraps its content in a SafeArea (top: true), so
              // outside the Scaffold bottom slot it inherits the status-bar
              // inset and adds it as empty space above the icons. Strip the
              // padding here so the bar hugs its destinations.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  height: 72,
                  selectedIndex: currentTab.index - 1,
                  onDestinationSelected: (index) {
                    onSelect(AppTab.values[index + 1]);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.weekend_outlined),
                      selectedIcon: Icon(Icons.weekend_rounded),
                      label: 'Room',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.forum_outlined),
                      selectedIcon: Icon(Icons.forum_rounded),
                      label: 'Hall',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.chat_bubble_outline_rounded),
                      selectedIcon: Icon(Icons.chat_bubble_rounded),
                      label: 'Chat',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
