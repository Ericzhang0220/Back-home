import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  double _musicVolume = 0.65;
  String _textSize = 'Medium';

  @override
  Widget build(BuildContext context) {
    return AppPage(
      eyebrow: 'Profile + Settings',
      title: 'Your comfort profile',
      subtitle:
          'Personal info, mood history, accessibility controls, and account settings live together here.',
      trailing: const InfoPill(
        icon: Icons.local_fire_department_rounded,
        label: 'Streak',
        value: '11 days',
        tint: Color(0xFFF7DFC8),
      ),
      children: [
        SoftCard(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8F2), Color(0xFFEEDCCD)],
          ),
          child: Row(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.nightlight_round,
                  color: AppColors.clay,
                  size: 34,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Eric\'s room card',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Level 8 listener • 238 likes earned • 4 achievements this month',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Last month activity',
          subtitle: 'Mood and happiness should be readable at a glance.',
        ),
        const SizedBox(height: 14),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoodBarChart(
                values: [0.55, 0.72, 0.46, 0.82, 0.68, 0.76, 0.88],
                labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                emoji: ['🙂', '😊', '😐', '😄', '🙂', '😌', '😁'],
              ),
              SizedBox(height: 18),
              Text(
                'Average happiness level: 74%',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Reading comfort',
          subtitle:
              'Text size should be easy to switch without leaving the page.',
        ),
        const SizedBox(height: 14),
        SoftCard(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in const ['Small', 'Medium', 'Large'])
                ChoiceChip(
                  label: Text(option),
                  selected: _textSize == option,
                  onSelected: (_) {
                    setState(() {
                      _textSize = option;
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Audio settings',
          subtitle: 'Background music should feel adjustable, not buried.',
        ),
        const SizedBox(height: 14),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note_rounded, color: AppColors.clay),
                  const SizedBox(width: 10),
                  Text(
                    'Background music volume',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${(_musicVolume * 100).round()}%',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              Slider(
                value: _musicVolume,
                onChanged: (value) {
                  setState(() {
                    _musicVolume = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Account actions',
          subtitle: 'Keep sensitive actions separated from everyday controls.',
        ),
        const SizedBox(height: 14),
        const _SettingsAction(
          icon: Icons.logout_rounded,
          title: 'Log out',
          detail: 'Sign out from this device.',
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
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.detail,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
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
    );
  }
}
