import 'package:flutter/material.dart';

import '../auth/app_auth_controller.dart';
import 'mood_calendar_screen.dart';
import '../settings/app_settings_controller.dart';
import '../widgets/app_ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.settingsController,
    required this.authController,
    super.key,
  });

  final AppSettingsController settingsController;
  final AppAuthController authController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([settingsController, authController]),
      builder: (context, _) {
        final selectedTextSize = settingsController.readingComfort;
        final musicVolume = settingsController.musicVolume;
        final currentUser = authController.currentUser;
        final profileName = currentUser?.displayName?.trim().isNotEmpty == true
            ? currentUser!.displayName!.trim()
            : currentUser?.phoneNumber ?? 'Your account';
        final accountHint =
            currentUser?.email ??
            currentUser?.phoneNumber ??
            'Signed in and saved on this device.';

        return AppPage(
          title: '',
          subtitle: '',
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/default.png',
                  width: 92,
                  height: 92,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Column(
                children: [
                  Text(
                    profileName,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    accountHint,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.28,
                  child: const InfoPill(
                    icon: Icons.favorite_rounded,
                    label: 'Likes',
                    value: '100',
                    tint: Color(0xFFF7DFC8),
                  ),
                ),
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.28,
                  child: const InfoPill(
                    icon: Icons.person_rounded,
                    label: 'Friends',
                    value: '100',
                    tint: Color(0xFFF7DFC8),
                  ),
                ),
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.28,
                  child: const InfoPill(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Active',
                    value: '11 days',
                    tint: Color(0xFFF7DFC8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Your happiness index for the past week:',
              titleSize: 20,
              subtitle: '',
            ),
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MoodCalendarScreen(),
                  ),
                );
              },
              child: SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Tap to open monthly mood calendar',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: AppColors.clay,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    MoodBarChart(
                      values: [0.55, 0.72, 0.46, 0.82, 0.68, 0.76, 0.88],
                      labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                      emoji: ['🙂', '😊', '😐', '😄', '🙂', '😌', '😁'],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Average happiness level: 74%',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Reading comfort'),
            const SizedBox(height: 12),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in ReadingComfort.values)
                        ChoiceChip(
                          label: Text(option.label),
                          selected: selectedTextSize == option,
                          onSelected: (_) {
                            settingsController.setReadingComfort(option);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Applies across the app and stays saved for next time.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Audio settings'),
            const SizedBox(height: 12),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.clay,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Music volume',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        '${(musicVolume * 100).round()}%',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  Slider(
                    value: musicVolume,
                    onChanged: settingsController.setMusicVolume,
                  ),
                  Text(
                    musicVolume <= 0
                        ? 'Muted. Raise the slider to resume your playlist.'
                        : 'Music Time!',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Account actions',
              subtitle:
                  'Keep sensitive actions separated from everyday controls.',
            ),
            const SizedBox(height: 14),
            _SettingsAction(
              icon: Icons.logout_rounded,
              title: 'Log out',
              detail: 'Sign out from this device.',
              onTap: () => _confirmSignOut(context),
            ),
            const SizedBox(height: 12),
            const _SettingsAction(
              icon: Icons.delete_outline_rounded,
              title: 'Delete account',
              detail: 'Permanently remove profile data and room progress.',
              destructive: true,
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final didConfirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SoftCard(
              color: Colors.white.withValues(alpha: 0.94),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Log out now?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The next app open will show the login screen again until you sign back in.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Stay signed in'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Log out'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (didConfirm != true || !context.mounted) {
      return;
    }

    try {
      await authController.signOut();
    } on AuthFlowException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.detail,
    this.destructive = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: SoftCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: destructive
                      ? const Color(0xFFF7DEDA)
                      : AppColors.blush.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: destructive ? const Color(0xFFC34A3F) : AppColors.clay,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: destructive ? const Color(0xFFC34A3F) : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(detail, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
