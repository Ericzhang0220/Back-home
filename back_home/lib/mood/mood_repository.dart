import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared mapping between the home check-in mood ids and a 0..1 happiness
/// value plus an emoji. Keep these ids in sync with the home screen choices.
class MoodScale {
  const MoodScale._();

  static const Map<String, double> values = {
    'very_happy': 1.0,
    'happy': 0.75,
    'neutral': 0.5,
    'sad': 0.25,
    'crying': 0.0,
  };

  static const Map<String, String> emojis = {
    'very_happy': '😄',
    'happy': '🙂',
    'neutral': '😐',
    'sad': '☹️',
    'crying': '😭',
  };

  static double valueFor(String moodId) => values[moodId] ?? 0.5;

  static String emojiFor(String moodId) => emojis[moodId] ?? '🙂';
}

class MoodEntry {
  const MoodEntry({
    required this.date,
    required this.moodId,
    required this.value,
    required this.emoji,
  });

  final DateTime date;
  final String moodId;
  final double value;
  final String emoji;
}

/// Reads and writes a user's daily mood check-ins, stored one document per day
/// under `users/{uid}/moodEntries/{yyyy-MM-dd}`.
class MoodRepository {
  MoodRepository(this.uid);

  final String uid;

  CollectionReference<Map<String, dynamic>> get _entries => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('moodEntries');

  static String dateId(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> saveMood({required DateTime date, required String moodId}) {
    final id = dateId(date);
    return _entries.doc(id).set({
      'moodId': moodId,
      'value': MoodScale.valueFor(moodId),
      'emoji': MoodScale.emojiFor(moodId),
      'date': id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Streams the most recent [days] check-ins keyed by their `yyyy-MM-dd` id.
  Stream<Map<String, MoodEntry>> watchRecent({int days = 31}) {
    return _entries
        .orderBy('date', descending: true)
        .limit(days)
        .snapshots()
        .map((snapshot) {
          final entries = <String, MoodEntry>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final dateString = (data['date'] as String?) ?? doc.id;
            final parsed = DateTime.tryParse(dateString);
            if (parsed == null) {
              continue;
            }
            final moodId = (data['moodId'] as String?) ?? 'neutral';
            entries[dateString] = MoodEntry(
              date: parsed,
              moodId: moodId,
              value:
                  (data['value'] as num?)?.toDouble() ??
                  MoodScale.valueFor(moodId),
              emoji: (data['emoji'] as String?) ?? MoodScale.emojiFor(moodId),
            );
          }
          return entries;
        });
  }
}

/// The trailing-seven-day view backing the happiness index chart. Missing days
/// carry a `null` value so the chart can draw them as empty bars.
class WeeklyMoodSummary {
  WeeklyMoodSummary({
    required this.values,
    required this.labels,
    required this.emoji,
    required this.averagePercent,
    required this.hasData,
  });

  final List<double?> values;
  final List<String> labels;
  final List<String> emoji;
  final int averagePercent;
  final bool hasData;

  static const List<String> _weekdayInitials = [
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  factory WeeklyMoodSummary.fromEntries(
    Map<String, MoodEntry> entries, {
    required DateTime today,
  }) {
    final startOfToday = DateTime(today.year, today.month, today.day);
    final values = <double?>[];
    final labels = <String>[];
    final emoji = <String>[];
    final present = <double>[];

    for (var daysAgo = 6; daysAgo >= 0; daysAgo--) {
      final day = startOfToday.subtract(Duration(days: daysAgo));
      labels.add(_weekdayInitials[(day.weekday - 1) % 7]);
      final entry = entries[MoodRepository.dateId(day)];
      if (entry != null) {
        values.add(entry.value);
        emoji.add(entry.emoji);
        present.add(entry.value);
      } else {
        values.add(null);
        emoji.add('·');
      }
    }

    final average = present.isEmpty
        ? 0
        : ((present.reduce((a, b) => a + b) / present.length) * 100).round();

    return WeeklyMoodSummary(
      values: values,
      labels: labels,
      emoji: emoji,
      averagePercent: average,
      hasData: present.isNotEmpty,
    );
  }
}
