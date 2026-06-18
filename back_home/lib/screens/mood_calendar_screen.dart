import 'package:flutter/material.dart';

import '../mood/mood_repository.dart';
import '../widgets/app_ui.dart';

class MoodCalendarScreen extends StatefulWidget {
  const MoodCalendarScreen({super.key, this.uid});

  final String? uid;

  @override
  State<MoodCalendarScreen> createState() => _MoodCalendarScreenState();
}

class _MoodCalendarScreenState extends State<MoodCalendarScreen> {
  static const List<String> _weekdayLabels = [
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  static const List<String> _monthLabels = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = List<int>.generate(
      5,
      (index) => DateTime.now().year - 2 + index,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                      Expanded(
                        child: Text(
                          'Mood Calendar',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _YearDropdown(
                    value: _selectedYear,
                    years: years,
                    onChanged: (year) {
                      if (year == null) {
                        return;
                      }
                      setState(() {
                        _selectedYear = year;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: Row(
                      children: [
                        for (final label in _weekdayLabels)
                          Expanded(
                            child: Center(
                              child: Text(
                                label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: widget.uid == null
                      ? _buildMonthList(const {})
                      : StreamBuilder<Map<String, MoodEntry>>(
                          stream: MoodRepository(
                            widget.uid!,
                          ).watchYear(_selectedYear),
                          builder: (context, snapshot) {
                            return _buildMonthList(snapshot.data ?? const {});
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthList(Map<String, MoodEntry> entries) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      itemCount: _monthLabels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 20),
      itemBuilder: (context, index) {
        final month = index + 1;
        final monthDate = DateTime(_selectedYear, month);
        return _MonthSection(
          title: _monthLabels[index],
          cells: _buildMonthCells(monthDate, entries),
        );
      },
    );
  }

  List<_MoodDay?> _buildMonthCells(
    DateTime month,
    Map<String, MoodEntry> entries,
  ) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final leadingEmptyCells = firstDayOfMonth.weekday - 1;
    final totalDays = lastDayOfMonth.day;

    final cells = <_MoodDay?>[];
    for (var index = 0; index < leadingEmptyCells; index++) {
      cells.add(null);
    }
    for (var day = 1; day <= totalDays; day++) {
      final date = DateTime(month.year, month.month, day);
      final entry = entries[MoodRepository.dateId(date)];
      cells.add(
        _MoodDay(
          date: date,
          mood: entry == null ? null : _moodTypeForId(entry.moodId),
          isFuture: date.isAfter(today),
        ),
      );
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return cells;
  }

  _MoodType? _moodTypeForId(String moodId) {
    return switch (moodId) {
      'very_happy' => _MoodType.veryHappy,
      'happy' => _MoodType.happy,
      'neutral' => _MoodType.neutral,
      'sad' => _MoodType.sad,
      'crying' => _MoodType.crying,
      _ => null,
    };
  }
}

class _YearDropdown extends StatelessWidget {
  const _YearDropdown({
    required this.value,
    required this.years,
    required this.onChanged,
  });

  final int value;
  final List<int> years;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          borderRadius: BorderRadius.circular(16),
          items: [
            for (final year in years)
              DropdownMenuItem<int>(
                value: year,
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: AppColors.clay,
                    ),
                    const SizedBox(width: 10),
                    Text('$year'),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({required this.title, required this.cells});

  final String title;
  final List<_MoodDay?> cells;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      color: Colors.white.withValues(alpha: 0.42),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 8,
              childAspectRatio: 0.84,
            ),
            itemBuilder: (context, index) {
              final cell = cells[index];
              if (cell == null) {
                return const SizedBox.shrink();
              }

              return _MoodDayCell(
                dayNumber: cell.date.day,
                mood: cell.mood,
                isFuture: cell.isFuture,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MoodDay {
  const _MoodDay({
    required this.date,
    required this.mood,
    required this.isFuture,
  });

  final DateTime date;
  final _MoodType? mood;
  final bool isFuture;
}

enum _MoodType {
  veryHappy('😄'),
  happy('🙂'),
  neutral('😐'),
  sad('☹️'),
  crying('😭');

  const _MoodType(this.emoji);

  final String emoji;
}

class _MoodDayCell extends StatelessWidget {
  const _MoodDayCell({
    required this.dayNumber,
    required this.mood,
    required this.isFuture,
  });

  final int dayNumber;
  final _MoodType? mood;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final hasMood = mood != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Text(
          '$dayNumber',
          textScaler: TextScaler.noScaling,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: isFuture ? AppColors.muted : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasMood
                ? _backgroundColorForMood(mood!)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: hasMood ? Colors.transparent : AppColors.stroke,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              hasMood ? mood!.emoji : '',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              strutStyle: const StrutStyle(
                fontSize: 23.5,
                height: 1.035,
                forceStrutHeight: true,
              ),
              style: const TextStyle(
                fontSize: 23.5,
                height: 1.035,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _backgroundColorForMood(_MoodType mood) {
    return switch (mood) {
      _MoodType.veryHappy => const Color.fromARGB(255, 0, 203, 10),
      _MoodType.happy => const Color.fromARGB(255, 170, 255, 73),
      _MoodType.neutral => const Color.fromARGB(255, 255, 255, 255),
      _MoodType.sad => const Color.fromARGB(255, 243, 225, 61),
      _MoodType.crying => const Color.fromARGB(255, 245, 67, 67),
    };
  }
}
