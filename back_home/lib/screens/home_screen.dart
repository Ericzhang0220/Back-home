import 'package:flutter/material.dart';

import '../auth/app_auth_controller.dart';
import '../mood/mood_repository.dart';
import '../widgets/app_ui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.authController,
    required this.onOpenRoom,
    required this.onOpenHall,
    required this.onOpenChat,
    required this.onOpenShop,
    required this.onOpenAchievements,
  });

  final AppAuthController authController;
  final VoidCallback onOpenRoom;
  final VoidCallback onOpenHall;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenShop;
  final VoidCallback onOpenAchievements;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedMoodId;
  String _selectedNeedId = 'comfort';
  bool _hasConfirmedMood = false;

  static const List<_MoodChoice> _moodChoices = [
    _MoodChoice(
      id: 'very_happy',
      emoji: '😄',
      label: 'Very happy',
      tint: Color.fromARGB(255, 0, 203, 10),
      message:
          'Hold onto that brightness. Your room is ready whenever you want to settle in.',
    ),
    _MoodChoice(
      id: 'happy',
      emoji: '🙂',
      label: 'Good',
      tint: Color.fromARGB(255, 170, 255, 73),
      message:
          'Good is worth noticing. Step into your room and let the evening stay gentle.',
    ),
    _MoodChoice(
      id: 'neutral',
      emoji: '😐',
      label: 'Neutral',
      tint: Color.fromARGB(255, 255, 255, 255),
      message:
          'A quiet middle is still a real check-in. Your room can meet you there.',
    ),
    _MoodChoice(
      id: 'sad',
      emoji: '☹️',
      label: 'Low',
      tint: Color.fromARGB(255, 243, 225, 61),
      message:
          'Low days can move slowly. Your room is here for a softer landing.',
    ),
    _MoodChoice(
      id: 'crying',
      emoji: '😭',
      label: 'Bad',
      tint: Color(0xFFE45757),
      message:
          'That sounds heavy. Come back home and take one small breath at a time.',
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
    final selectedMoodId = _selectedMoodId;
    final selectedMood = selectedMoodId == null
        ? null
        : _moodChoices.firstWhere((choice) => choice.id == selectedMoodId);

    return SizedBox(
      height: double.infinity,
      child: Stack(
        children: [
          AppPage(
            title: '',
            subtitle: '',
            padding: const EdgeInsets.only(
              top: 30,
              left: 23,
              right: 20,
              bottom: 140,
            ),
            children: [
              const StaggeredFadeIn(child: _HomeHeader()),
              const SizedBox(height: 18),
              StaggeredFadeIn(
                delay: const Duration(milliseconds: 170),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.025),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: (_hasConfirmedMood && selectedMood != null)
                      ? _MoodConfirmationCard(
                          key: ValueKey('confirmed-${selectedMood.id}'),
                          mood: selectedMood,
                        )
                      : _DailyCheckInCard(
                          key: const ValueKey('check-in-card'),
                          moodChoices: _moodChoices,
                          needChoices: _needChoices,
                          selectedMoodId: _selectedMoodId,
                          selectedNeedId: _selectedNeedId,
                          onMoodSelected: _handleMoodTap,
                          onNeedSelected: (id) {
                            setState(() {
                              _selectedNeedId = id;
                            });
                          },
                          summary: selectedMood == null
                              ? ''
                              : 'You marked ${selectedMood.label.toLowerCase()}. We can use this later for your calendar and weekly mood chart.',
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 25,
            right: 30,
            child: IgnorePointer(
              ignoring: !_hasConfirmedMood,
              child: AnimatedOpacity(
                opacity: _hasConfirmedMood ? 1 : 0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: _hasConfirmedMood
                      ? Offset.zero
                      : const Offset(0, 0.1),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: SizedBox(
                    width: 165,
                    height: 60,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: const Color.fromARGB(
                          255,
                          255,
                          210,
                          75,
                        ),
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleMoodTap(String id) {
    final isConfirming = _selectedMoodId == id;
    final wasConfirmed = _hasConfirmedMood;
    setState(() {
      if (isConfirming) {
        _hasConfirmedMood = true;
      } else {
        _selectedMoodId = id;
        _hasConfirmedMood = false;
      }
    });

    // Persist the mood once, on the transition into a confirmed check-in.
    if (isConfirming && !wasConfirmed) {
      _persistMood(id);
    }
  }

  Future<void> _persistMood(String moodId) async {
    final uid = widget.authController.currentUser?.uid;
    if (uid == null) {
      return;
    }
    try {
      await MoodRepository(uid).saveMood(date: DateTime.now(), moodId: moodId);
    } catch (error) {
      debugPrint('Could not save mood check-in: $error');
    }
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 0, 0, 0),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Username',
                style: TextStyle(
                  color: Color.fromARGB(255, 0, 0, 0),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        const _HomeIllustration(),
      ],
    );
  }
}

class _DailyCheckInCard extends StatelessWidget {
  const _DailyCheckInCard({
    super.key,
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
  final String? selectedMoodId;
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

class _MoodConfirmationCard extends StatelessWidget {
  const _MoodConfirmationCard({super.key, required this.mood});

  final _MoodChoice mood;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [mood.tint.withValues(alpha: 0.26), const Color(0xFFFFF8F1)],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      radius: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: mood.tint, shape: BoxShape.circle),
            child: Text(mood.emoji, style: const TextStyle(fontSize: 29)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Checked in as ${mood.label.toLowerCase()}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  mood.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
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
    required this.message,
  });

  final String id;
  final String emoji;
  final String label;
  final Color tint;
  final String message;
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
