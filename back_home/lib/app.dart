import 'dart:ui';

import 'package:flutter/material.dart';

import 'screens/achievements_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/hall_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/room_screen.dart';
import 'screens/shop_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';

class BackHomeApp extends StatelessWidget {
  const BackHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Back Home',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShell(),
    );
  }
}

enum AppTab { home, room, hall, chat, profile }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _currentTab = AppTab.home;

  void _selectTab(AppTab tab) {
    setState(() {
      _currentTab = tab;
    });
  }

  Future<void> _openShop() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));
  }

  Future<void> _openAchievements() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        onOpenRoom: () => _selectTab(AppTab.room),
        onOpenHall: () => _selectTab(AppTab.hall),
        onOpenChat: () => _selectTab(AppTab.chat),
        onOpenShop: _openShop,
        onOpenAchievements: _openAchievements,
      ),
      RoomScreen(onOpenShop: _openShop),
      const HallScreen(),
      const ChatScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color.fromARGB(0, 212, 255, 18),
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: IndexedStack(index: _currentTab.index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: (_currentTab != AppTab.home)
          ? Container(
              color: Color.fromARGB(255, 255, 221, 198),
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
                        // NavigationDestination(
                        //   icon: Icon(Icons.home_outlined),
                        //   selectedIcon: Icon(Icons.home_rounded),
                        //   label: 'Home',
                        // ),
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
