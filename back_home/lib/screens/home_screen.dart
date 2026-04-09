import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenRoom,
    required this.onOpenHall,
    required this.onOpenChat,
    required this.onOpenShop,
    required this.onOpenAchievements,
  });

  final VoidCallback onOpenRoom;
  final VoidCallback onOpenHall;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenShop;
  final VoidCallback onOpenAchievements;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedMoodId = 'happy';
  String _selectedNeedId = 'comfort';

  static const List<_MoodChoice> _moodChoices = [
    _MoodChoice(
      id: 'very_happy',
      emoji: '😄',
      label: 'Very happy',
      tint: Color(0xFF2E7D32),
    ),
    _MoodChoice(
      id: 'happy',
      emoji: '🙂',
      label: 'Good',
      tint: Color(0xFF8BC34A),
    ),
    _MoodChoice(
      id: 'neutral',
      emoji: '😐',
      label: 'Neutral',
      tint: Color(0xFFF3C75F),
    ),
    _MoodChoice(id: 'sad', emoji: '☹️', label: 'Low', tint: Color(0xFFF39C3D)),
    _MoodChoice(
      id: 'crying',
      emoji: '😭',
      label: 'Bad',
      tint: Color(0xFFE45757),
    ),
  ];

  static const List<_NeedChoice> _needChoices = [
    _NeedChoice(id: 'comfort', label: 'Comfort'),
    _NeedChoice(id: 'rest', label: 'Rest'),
    _NeedChoice(id: 'company', label: 'Company'),
    _NeedChoice(id: 'focus', label: 'Focus'),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedMood = _moodChoices.firstWhere(
      (choice) => choice.id == _selectedMoodId,
    );

    return AppPage(
      title: 'Welcome Back',
      subtitle: 'Username',
      trailing: const _HomeIllustration(),
      padding: const EdgeInsets.only(top: 30, left: 23, right: 20, bottom: 140),
      children: [
        const SizedBox(height: 18),
        _DailyCheckInCard(
          moodChoices: _moodChoices,
          needChoices: _needChoices,
          selectedMoodId: _selectedMoodId,
          selectedNeedId: _selectedNeedId,
          onMoodSelected: (id) {
            setState(() {
              _selectedMoodId = id;
            });
          },
          onNeedSelected: (id) {
            setState(() {
              _selectedNeedId = id;
            });
          },
          summary:
              'You marked ${selectedMood.label.toLowerCase()}. We can use this later for your calendar and weekly mood chart.',
        ),
        const SizedBox(height: 128),
        Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 165,
            height: 60,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: const Color.fromARGB(255, 255, 210, 75),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: widget.onOpenRoom,
              icon: Image.asset(
                'assets/Arrow 2.png',
                color: const Color.fromARGB(255, 0, 0, 0),
                width: 28,
              ),
              label: const Text(
                'Open room',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color.fromARGB(255, 0, 0, 0),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyCheckInCard extends StatelessWidget {
  const _DailyCheckInCard({
    required this.moodChoices,
    required this.needChoices,
    required this.selectedMoodId,
    required this.selectedNeedId,
    required this.onMoodSelected,
    required this.onNeedSelected,
    required this.summary,
  });

  final List<_MoodChoice> moodChoices;
  final List<_NeedChoice> needChoices;
  final String selectedMoodId;
  final String selectedNeedId;
  final ValueChanged<String> onMoodSelected;
  final ValueChanged<String> onNeedSelected;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFF8F1), Color(0xFFF9E8D9)],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      radius: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Daily check-in',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.clay,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How are you feeling today?',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontSize: 25),
          ),
          const SizedBox(height: 10),
          // Text(
          //   'A quick mood entry here can later feed your monthly calendar and profile charts.',
          //   style: Theme.of(context).textTheme.bodyMedium,
          // ),
          // const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final mood in moodChoices)
                _MoodChoiceChip(
                  mood: mood,
                  selected: selectedMoodId == mood.id,
                  onTap: () => onMoodSelected(mood.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Text(
          //   'What would help most tonight?',
          //   style: Theme.of(context).textTheme.titleMedium,
          // ),
          // const SizedBox(height: 12),
          // Wrap(
          //   spacing: 10,
          //   runSpacing: 10,
          //   children: [
          //     for (final need in needChoices)
          //       _NeedChip(
          //         label: need.label,
          //         selected: selectedNeedId == need.id,
          //         onTap: () => onNeedSelected(need.id),
          //       ),
          //   ],
          // ),
          // const SizedBox(height: 18),
          // Container(
          //   padding: const EdgeInsets.all(14),
          //   decoration: BoxDecoration(
          //     color: Colors.white.withValues(alpha: 0.74),
          //     borderRadius: BorderRadius.circular(20),
          //     border: Border.all(color: AppColors.stroke),
          //   ),
          //   child: Row(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       Container(
          //         width: 38,
          //         height: 38,
          //         decoration: BoxDecoration(
          //           color: AppColors.blush.withValues(alpha: 0.8),
          //           borderRadius: BorderRadius.circular(14),
          //         ),
          //         child: const Icon(
          //           Icons.favorite_rounded,
          //           color: AppColors.clay,
          //           size: 20,
          //         ),
          //       ),
          //       const SizedBox(width: 12),
          //       Expanded(
          //         child: Text(
          //           summary,
          //           style: Theme.of(context).textTheme.bodyMedium,
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
        ],
      ),
    );
  }
}

class _MoodChoice {
  const _MoodChoice({
    required this.id,
    required this.emoji,
    required this.label,
    required this.tint,
  });

  final String id;
  final String emoji;
  final String label;
  final Color tint;
}

class _NeedChoice {
  const _NeedChoice({required this.id, required this.label});

  final String id;
  final String label;
}

class _MoodChoiceChip extends StatelessWidget {
  const _MoodChoiceChip({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final _MoodChoice mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          width: 94,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? mood.tint.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? mood.tint : AppColors.stroke,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? mood.tint : mood.tint.withValues(alpha: 1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(mood.emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: 8),
              Text(
                mood.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeIllustration extends StatelessWidget {
  const _HomeIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      height: 154,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 18,
            left: 24,
            right: 24,
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3C7),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.stroke),
              ),
            ),
          ),
          Positioned(
            top: 28,
            left: 34,
            child: Container(
              height: 26,
              width: 22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            top: 28,
            right: 34,
            child: Container(
              height: 26,
              width: 22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            left: 18,
            right: 18,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFD89D7F),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          Positioned(
            bottom: 44,
            left: 30,
            child: Container(
              height: 24,
              width: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFFCEEDF),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 22,
            right: 22,
            child: Container(
              width: 20,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF8CB094),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
