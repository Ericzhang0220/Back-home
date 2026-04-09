import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'audio/background_music_controller.dart';
import 'rooms/room_state.dart';
import 'screens/achievements_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/hall_screen.dart';
import 'screens/home_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController();
    _musicController = BackgroundMusicController(
      settingsController: _settingsController,
    );
    unawaited(_initializeControllers());
  }

  @override
  void dispose() {
    unawaited(_musicController.dispose());
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
          home: AppShell(settingsController: _settingsController),
        );
      },
    );
  }
}

enum AppTab { home, room, hall, chat, profile }

class AppShell extends StatefulWidget {
  const AppShell({required this.settingsController, super.key});

  final AppSettingsController settingsController;

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

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  void _selectTab(AppTab tab) {
    setState(() {
      _currentTab = tab;
      if (tab != AppTab.home) {
        _initializedTabs.add(tab);
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
          onOpenShop: _openShop,
          isActive: _currentTab == AppTab.room,
        );
      case AppTab.hall:
        return const KeyedSubtree(
          key: ValueKey(AppTab.hall),
          child: SafeArea(child: HallScreen()),
        );
      case AppTab.chat:
        return const KeyedSubtree(
          key: ValueKey(AppTab.chat),
          child: SafeArea(child: ChatScreen()),
        );
      case AppTab.profile:
        return KeyedSubtree(
          key: const ValueKey(AppTab.profile),
          child: SafeArea(
            child: ProfileScreen(settingsController: widget.settingsController),
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

    return Scaffold(
      backgroundColor: isRoomTab
          ? const Color(0xFF080706)
          : const Color.fromARGB(0, 212, 255, 18),
      body: _currentTab == AppTab.home
          ? Stack(
              children: [
                AmbientBackground(showSideGlow: false),
                SafeArea(child: _buildHomePage()),
              ],
            )
          : Stack(
              children: [
                if (!isRoomTab) const AmbientBackground(showSideGlow: true),
                Positioned.fill(child: _buildTabbedPages()),
              ],
            ),
      bottomNavigationBar: (_currentTab != AppTab.home)
          ? Container(
              color: const Color.fromARGB(255, 255, 221, 198),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: NavigationBar(
                      selectedIndex: _currentTab.index - 1,
                      onDestinationSelected: (index) {
                        _selectTab(AppTab.values[index + 1]);
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
            )
          : null,
    );
  }
}
