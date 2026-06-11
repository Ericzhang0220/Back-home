import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../audio/background_music_controller.dart';
import '../auth/app_auth_controller.dart';
import '../settings/app_settings_controller.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/settings_gear_icon.dart';
import 'mood_calendar_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.settingsController,
    required this.musicController,
    required this.authController,
    super.key,
  });

  final AppSettingsController settingsController;
  final BackgroundMusicController musicController;
  final AppAuthController authController;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.settingsController,
        widget.musicController,
        widget.authController,
      ]),
      builder: (context, _) {
        final currentUser = widget.authController.currentUser;
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
          leading: IconButton(
            padding: const EdgeInsets.only(right: 6),
            icon: const Icon(Icons.mail_outline),
            onPressed: () => Navigator.of(context).pop(),
          ),
          trailing: IconButton(
            icon: const SettingsGearIcon(),
            tooltip: 'Profile settings',
            onPressed: _openSettings,
          ),
          children: [
            Center(
              child: ProfileAvatar(
                displayName: profileName,
                photoUrl: currentUser?.photoURL,
                localPhotoPath: widget.authController.localProfilePhotoPath,
                radius: 46,
                showEditBadge: true,
                onTap: widget.authController.isBusy ? null : _pickProfilePhoto,
                heroTag: 'profile-avatar-${currentUser?.uid ?? 'me'}',
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
            const _ProfileStatsRow(
              showLikes: true,
              showFriends: true,
              showActive: true,
              tint: Color(0xFFF7DFC8),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Your happiness index for the past week:',
              titleSize: 20,
              subtitle: '',
            ),
            _HappinessIndexCard(
              isInteractive: true,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MoodCalendarScreen(),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileSettingsScreen(
          settingsController: widget.settingsController,
          musicController: widget.musicController,
          authController: widget.authController,
        ),
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 86,
    );
    if (pickedImage == null) {
      return;
    }

    try {
      await widget.authController.updateProfilePhoto(File(pickedImage.path));
      if (!mounted) {
        return;
      }
      final hasUploadedUrl =
          widget.authController.currentUser?.photoURL?.trim().isNotEmpty ==
          true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasUploadedUrl
                ? 'Profile photo updated.'
                : 'Photo set locally. It will upload once Firebase Storage is enabled.',
          ),
        ),
      );
    } on AuthFlowException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _ProfileSettingsScreen extends StatelessWidget {
  const _ProfileSettingsScreen({
    required this.settingsController,
    required this.musicController,
    required this.authController,
  });

  final AppSettingsController settingsController;
  final BackgroundMusicController musicController;
  final AppAuthController authController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        settingsController,
        musicController,
        authController,
      ]),
      builder: (context, _) {
        final selectedTextSize = settingsController.readingComfort;
        final musicVolume = settingsController.musicVolume;
        final currentTrackTitle = musicController.currentTrackTitle;
        final currentTrackSubtitle = musicController.currentTrackSubtitle;

        return Scaffold(
          backgroundColor: AppColors.cream,
          appBar: AppBar(
            backgroundColor: AppColors.cream.withValues(alpha: 0.94),
            foregroundColor: AppColors.ink,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            leading: BackButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ButtonStyle(
                iconSize: selectedTextSize == ReadingComfort.small
                    ? WidgetStateProperty.all(20)
                    : selectedTextSize == ReadingComfort.medium
                    ? WidgetStateProperty.all(24)
                    : WidgetStateProperty.all(28),
              ),
            ),
          ),
          body: Stack(
            children: [
              const AmbientBackground(showSideGlow: true),
              SafeArea(
                top: false,
                child: AppPage(
                  title: '',
                  subtitle: '',
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                  children: [
                    const SectionHeader(
                      title: 'Public profile visibility',
                      subtitle: 'Choose what other people can see.',
                    ),
                    const SizedBox(height: 12),
                    SoftCard(
                      child: Column(
                        children: [
                          _SettingsSwitchRow(
                            title: 'Happiness index',
                            detail: 'Show the weekly mood chart publicly.',
                            value: settingsController.showHappinessIndex,
                            onChanged: (value) {
                              settingsController.setPublicProfileVisibility(
                                showHappinessIndex: value,
                              );
                              _syncVisibility(context);
                            },
                          ),
                          const Divider(),
                          _SettingsSwitchRow(
                            title: 'Likes',
                            detail: 'Show the likes stat pill publicly.',
                            value: settingsController.showLikesStat,
                            onChanged: (value) {
                              settingsController.setPublicProfileVisibility(
                                showLikesStat: value,
                              );
                              _syncVisibility(context);
                            },
                          ),
                          const Divider(),
                          _SettingsSwitchRow(
                            title: 'Friends',
                            detail: 'Show the friends stat pill publicly.',
                            value: settingsController.showFriendsStat,
                            onChanged: (value) {
                              settingsController.setPublicProfileVisibility(
                                showFriendsStat: value,
                              );
                              _syncVisibility(context);
                            },
                          ),
                          const Divider(),
                          _SettingsSwitchRow(
                            title: 'Active streak',
                            detail: 'Show the active-days stat publicly.',
                            value: settingsController.showActiveStat,
                            onChanged: (value) {
                              settingsController.setPublicProfileVisibility(
                                showActiveStat: value,
                              );
                              _syncVisibility(context);
                            },
                          ),
                        ],
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
                                    settingsController.setReadingComfort(
                                      option,
                                    );
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
                    const SizedBox(height: 28),
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
                                'Apple Music',
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
                          if (currentTrackTitle != null) ...[
                            Text(
                              currentTrackTitle,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (currentTrackSubtitle != null)
                              Text(
                                currentTrackSubtitle,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            musicVolume <= 0
                                ? 'Muted. Raise the slider to resume Apple Music.'
                                : musicController.statusMessage,
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
                      detail:
                          'Permanently remove profile data and room progress.',
                      destructive: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _syncVisibility(BuildContext context) {
    unawaited(
      authController
          .updatePublicProfileVisibility(
            showHappinessIndex: settingsController.showHappinessIndex,
            showLikesStat: settingsController.showLikesStat,
            showFriendsStat: settingsController.showFriendsStat,
            showActiveStat: settingsController.showActiveStat,
          )
          .catchError((Object _) {
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not sync public profile visibility.'),
              ),
            );
          }),
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
      if (context.mounted) {
        Navigator.of(context).pop();
      }
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

class _ProfileStatsRow extends StatelessWidget {
  const _ProfileStatsRow({
    required this.showLikes,
    required this.showFriends,
    required this.showActive,
    this.tint = AppColors.blush,
  });

  final bool showLikes;
  final bool showFriends;
  final bool showActive;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[
      if (showLikes)
        InfoPill(
          icon: Icons.favorite_rounded,
          label: 'Likes',
          value: '100',
          tint: tint,
        ),
      if (showFriends)
        InfoPill(
          icon: Icons.person_rounded,
          label: 'Friends',
          value: '100',
          tint: tint,
        ),
      if (showActive)
        InfoPill(
          icon: Icons.local_fire_department_rounded,
          label: 'Active',
          value: '11 days',
          tint: tint,
        ),
    ];

    if (pills.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        for (var index = 0; index < pills.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(child: pills[index]),
        ],
      ],
    );
  }
}

class _HappinessIndexCard extends StatelessWidget {
  const _HappinessIndexCard({required this.isInteractive, this.onTap});

  final bool isInteractive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isInteractive
                    ? 'Tap to open monthly mood calendar'
                    : 'Weekly happiness index',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              if (isInteractive)
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
            emoji: const ['🙂', '😊', '😐', '😄', '🙂', '😌', '😁'],
          ),
          const SizedBox(height: 18),
          const Text(
            'Average happiness level: 74%',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );

    if (!isInteractive) {
      return card;
    }

    return GestureDetector(onTap: onTap, child: card);
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(detail, style: Theme.of(context).textTheme.bodyMedium),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.clay,
    );
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
