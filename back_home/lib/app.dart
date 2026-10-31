import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth/app_auth_controller.dart';
import 'auth/display_name_dialog.dart';
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
import 'widgets/bottom_navigation_reveal.dart';
import 'widgets/swipe_back_page_route.dart';
import 'keyboard/keyboard_host.dart';
import 'keyboard/keyboard_store.dart';

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
  late final RoomEditorController _shopRoomController;
  late final KeyboardStore _keyboards;
  String? _keyboardAccount;

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController();
    _useOfflineAuth = Firebase.apps.isEmpty;
    _authController = _useOfflineAuth
        ? AppAuthController.offline()
        : AppAuthController();
    _shopRoomController = RoomEditorController();
    _keyboards = KeyboardStore(_shopRoomController);
    _authController.addListener(_syncKeyboardAccount);
    _syncKeyboardAccount();
    _musicController = BackgroundMusicController(
      settingsController: _settingsController,
    );
    unawaited(_initializeControllers());
  }

  @override
  void dispose() {
    _authController.removeListener(_syncKeyboardAccount);
    _keyboards.dispose();
    _shopRoomController.dispose();
    unawaited(_musicController.shutdown());
    _authController.dispose();
    _settingsController.dispose();
    super.dispose();
  }

  void _syncKeyboardAccount() {
    final uid = _authController.currentUser?.uid ?? 'signed-out';
    if (_keyboardAccount == uid) return;
    _keyboardAccount = uid;
    unawaited(_keyboards.loadForAccount(uid));
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
              // Wraps every route and overlay, so tapping away from a text
              // field puts the keyboard down anywhere in the app. Translucent
              // so it never takes a tap from the widget under the finger:
              // buttons, fields and scrolls all still win the gesture arena,
              // and this only picks up the taps nothing else claimed.
              child: AppKeyboardHost(
                store: _keyboards,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  // Restore dark status icons after leaving a portrait card.
                  // Cards and app bars can override this nearer their artwork.
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: const SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarBrightness: Brightness.light,
                      statusBarIconBrightness: Brightness.dark,
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
          home: _AuthGate(
            roomController: _shopRoomController,
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
    required this.roomController,
    required this.settingsController,
    required this.musicController,
    required this.authController,
    this.bypassAuth = false,
  });

  final AppSettingsController settingsController;
  final BackgroundMusicController musicController;
  final AppAuthController authController;
  final bool bypassAuth;
  final RoomEditorController roomController;

  @override
  Widget build(BuildContext context) {
    if (bypassAuth) {
      return AppShell(
        roomController: roomController,
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
              roomController: roomController,
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
    this.roomController,
    required this.settingsController,
    required this.musicController,
    required this.authController,
    super.key,
  });

  final AppSettingsController settingsController;
  final BackgroundMusicController musicController;
  final AppAuthController authController;
  final RoomEditorController? roomController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _shellPageRoute = '/shell';
  final _pageNavigator = GlobalKey<NavigatorState>();
  bool _showingDetail = false;
  double _navDragDistance = 0;
  late final _pageObserver = _ShellNavigationObserver((showingDetail) {
    if (mounted && _showingDetail != showingDetail) {
      setState(() => _showingDetail = showingDetail);
    }
  });
  static const List<AppTab> _navigationTabs = [
    AppTab.room,
    AppTab.hall,
    AppTab.chat,
    AppTab.profile,
  ];

  late final RoomEditorController _roomController;
  final Set<AppTab> _initializedTabs = <AppTab>{};
  AppTab _currentTab = AppTab.home;

  // Room chrome (the shop button) auto-hides after a short hold, then fades out
  // slowly. The nav card has its own dock-style timing below.
  static const Duration _roomChromeFadeOut = Duration(seconds: 2);
  static const Duration _roomChromeHold = Duration(seconds: 4);

  Timer? _roomChromeFadeTimer;
  Timer? _roomChromeInputTimer;
  bool _roomChromeVisible = true;
  bool _roomChromeInteractive = true;
  bool _roomInSubview = false;

  // The floating nav card behaves like the macOS dock: it slides itself away
  // after a short idle window and comes back on a swipe up. The reveal target
  // deliberately stops short of the very bottom of the screen, which iOS
  // reserves for its own home-indicator gestures.
  static const Duration _navIdleHold = Duration(seconds: 4);
  static const Duration _navSlideIn = Duration(milliseconds: 260);
  static const Duration _navSlideOut = Duration(milliseconds: 380);
  static const double _navRevealZoneHeight = 56;
  static const double _navRevealZoneBottomGap = 22;

  Timer? _navHideTimer;
  bool _navVisible = false;
  bool _shopOpen = false;

  /// Guards the welcome prompt so a skipped name is not asked for again until
  /// the next launch.
  bool _hasAskedForDisplayName = false;

  @override
  void initState() {
    super.initState();
    _roomController = widget.roomController ?? RoomEditorController();
    _scheduleNavHide();
    // Reaching the shell means the account is verified and complete, so this is
    // the first moment a new person can be asked what to call them.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _promptForDisplayNameIfUnset(),
    );
  }

  Future<void> _promptForDisplayNameIfUnset() async {
    if (_hasAskedForDisplayName || !mounted) {
      return;
    }
    final user = widget.authController.currentUser;
    if (user == null || (user.displayName?.trim().isNotEmpty ?? false)) {
      return;
    }

    _hasAskedForDisplayName = true;
    await showDisplayNamePrompt(
      context,
      authController: widget.authController,
      isWelcome: true,
    );
  }

  @override
  void dispose() {
    _roomChromeFadeTimer?.cancel();
    _roomChromeInputTimer?.cancel();
    _navHideTimer?.cancel();
    if (widget.roomController == null) _roomController.dispose();
    super.dispose();
  }

  void _scheduleNavHide() {
    _navHideTimer?.cancel();
    _navHideTimer = Timer(_navIdleHold, () {
      if (!mounted || !_navVisible) {
        return;
      }
      setState(() => _navVisible = false);
    });
  }

  void _revealNav() {
    if (_shopOpen) return;
    if (!_navVisible) {
      setState(() => _navVisible = true);
    }
    _scheduleNavHide();
  }

  void _hideNav() {
    _navHideTimer?.cancel();
    if (_navVisible) {
      setState(() => _navVisible = false);
    }
  }

  void _selectTab(AppTab tab) {
    FocusManager.instance.primaryFocus?.unfocus();
    _pageNavigator.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _currentTab = tab;
      _showingDetail = false;
      _navVisible = true;
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
    _scheduleNavHide();
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
    // Room double-taps keep their camera/shop behavior. Reveal navigation with
    // an upward swipe instead.
  }

  void _handleRoomSubviewChanged(bool inSubview) {
    if (_roomInSubview == inSubview) {
      return;
    }
    if (!inSubview) {
      // Returning to the main room view leaves the nav bar hidden until the user
      // swipes it up — so drop any pending auto-hide and hide it.
      _roomChromeFadeTimer?.cancel();
      _roomChromeInputTimer?.cancel();
      _navHideTimer?.cancel();
    }
    setState(() {
      _roomInSubview = inSubview;
      _navVisible = false;
      if (!inSubview) {
        _roomChromeVisible = false;
        _roomChromeInteractive = false;
        _navVisible = false;
      }
    });
  }

  Future<void> _openShop() async {
    if (_shopOpen) return;
    _navHideTimer?.cancel();
    setState(() {
      _shopOpen = true;
      _navVisible = false;
    });
    try {
      final route = MaterialPageRoute<void>(
        builder: (_) => ShopScreen(controller: _roomController),
      );
      await _pageNavigator.currentState!.push(route);
      await route.completed;
    } finally {
      if (mounted) setState(() => _shopOpen = false);
    }
  }

  Future<void> _openAchievements() async {
    await _pageNavigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()),
    );
  }

  void _openOwnProfile() {
    _pageNavigator.currentState!.push<void>(
      SwipeBackPageRoute(
        builder: (_) => Scaffold(
          body: Stack(
            children: [
              const AmbientBackground(),
              SafeArea(
                child: ProfileScreen(
                  settingsController: widget.settingsController,
                  musicController: widget.musicController,
                  authController: widget.authController,
                  showBackButton: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            // Let the feed scroll behind the home indicator and floating nav.
            bottom: false,
            child: widget.authController.currentUser == null
                ? const Center(child: Text('Sign in to see the hall.'))
                : HallScreen(
                    authController: widget.authController,
                    onOwnProfileTap: _openOwnProfile,
                  ),
          ),
        );
      case AppTab.chat:
        return KeyedSubtree(
          key: const ValueKey(AppTab.chat),
          child: SafeArea(
            // Portraits paint behind the status bar; ChatScreen keeps its
            // controls inside their original top safe area.
            top: false,
            bottom: false,
            child: ChatScreen(
              authController: widget.authController,
              keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 0,
              navVisible: _navVisible,
              isActive: _currentTab == AppTab.chat,
            ),
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
    final useCompactRoomNav =
        isRoomTab && MediaQuery.orientationOf(context) == Orientation.landscape;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final navShown = !_shopOpen && _navVisible && !keyboardOpen;
    final navSlideOut = _currentTab == AppTab.chat
        ? const Duration(milliseconds: 180)
        : _navSlideOut;
    final revealZoneBottom = math.max(
      MediaQuery.paddingOf(context).bottom,
      _navRevealZoneBottomGap,
    );
    final backgroundColor = isRoomTab
        ? const Color(0xFF080706)
        : Colors.transparent;
    final shellPage = Scaffold(
      backgroundColor: backgroundColor,
      body: _currentTab == AppTab.home
          ? Stack(
              children: [
                const AmbientBackground(showSideGlow: false),
                SafeArea(bottom: false, child: _buildHomePage()),
              ],
            )
          : Stack(
              children: [
                if (!isRoomTab) const AmbientBackground(showSideGlow: true),
                Positioned.fill(child: _buildTabbedPages()),
              ],
            ),
    );

    return BottomNavigationReveal(
      enabled: !_shopOpen && !navShown && !keyboardOpen,
      allowDoubleTap:
          !_shopOpen &&
          !navShown &&
          !keyboardOpen &&
          (!isRoomTab || _showingDetail),
      bottomGap: revealZoneBottom,
      zoneHeight: _navRevealZoneHeight,
      onReveal: _revealNav,
      child: Scaffold(
        // Each content page handles its own keyboard resize. The navigation
        // overlay stays at the physical bottom and hides while typing.
        resizeToAvoidBottomInset: false,
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            Positioned.fill(
              child: NavigatorPopHandler<Object?>(
                onPopWithResult: (result) =>
                    _pageNavigator.currentState!.pop(result),
                child: Navigator(
                  key: _pageNavigator,
                  observers: [_pageObserver],
                  pages: [
                    MaterialPage<void>(
                      key: const ValueKey('shell-content'),
                      name: _shellPageRoute,
                      child: shellPage,
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              ),
            ),
            if (!_shopOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !navShown,
                  child: AnimatedSlide(
                    key: ValueKey(_currentTab == AppTab.home),
                    duration: navShown ? _navSlideIn : navSlideOut,
                    curve: navShown ? Curves.easeOutCubic : Curves.easeInCubic,
                    offset: Offset(0, navShown ? 0 : 1),
                    child: AnimatedOpacity(
                      duration: navShown ? _navSlideIn : navSlideOut,
                      curve: Curves.easeInOutCubic,
                      opacity: navShown ? 1 : 0,
                      child: GestureDetector(
                        onVerticalDragStart: (_) => _navDragDistance = 0,
                        onVerticalDragUpdate: (details) =>
                            _navDragDistance += details.delta.dy,
                        onVerticalDragEnd: (details) {
                          if (_navDragDistance > 24 ||
                              (details.primaryVelocity ?? 0) > 180) {
                            _hideNav();
                          }
                        },
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: useCompactRoomNav
                                  ? 560
                                  : double.infinity,
                            ),
                            child: _FloatingNavBar(
                              currentTab: _currentTab,
                              onSelect: _selectTab,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShellNavigationObserver extends NavigatorObserver {
  _ShellNavigationObserver(this.onChanged);
  final ValueChanged<bool> onChanged;
  int _revision = 0;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    final revision = ++_revision;
    final showingDetail =
        topRoute.settings.name != _AppShellState._shellPageRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (revision == _revision) onChanged(showingDetail);
    });
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
                  selectedIndex: math.max(0, currentTab.index - 1),
                  indicatorColor: currentTab == AppTab.home
                      ? Colors.transparent
                      : null,
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
