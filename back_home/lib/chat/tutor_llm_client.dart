import 'package:cloud_functions/cloud_functions.dart';

class TutorLlmClient {
  TutorLlmClient({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;

  Future<TutorReply> ask({
    required String sessionTitle,
    required List<TutorChatMessage> messages,
  }) async {
    String? latestUserMessage;
    for (final message in messages) {
      if (message.role == 'user') {
        latestUserMessage = message.text;
      }
    }

    try {
      final callable = (_functions ?? FirebaseFunctions.instance).httpsCallable(
        'askTutor',
      );
      final response = await callable.call<Map<String, dynamic>>({
        'sessionTitle': sessionTitle,
        'messages': messages.map((message) => message.toJson()).toList(),
      });
      final text = response.data['text'];

      if (text is String && text.trim().isNotEmpty) {
        return TutorReply(text: text.trim(), usedFallback: false);
      }
    } catch (_) {
      // The callable may be undeployed while UI work is in progress.
    }

    return TutorReply(
      text: _buildPlaceholderReply(latestUserMessage ?? sessionTitle),
      usedFallback: true,
    );
  }

  String _buildPlaceholderReply(String prompt) {
    final normalized = prompt.trim();
    final topic = normalized.isEmpty ? 'that' : normalized;

    return 'Placeholder tutor reply: I hear you on "$topic". Until the Gemini '
        'backend is deployed, try turning this into one clear next step, one '
        'thing you can ignore for now, and one question to revisit later.';
  }
}

class TutorChatMessage {
  const TutorChatMessage({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() {
    return {'role': role, 'text': text};
  }
}

class TutorReply {
  const TutorReply({required this.text, required this.usedFallback});

  final String text;
  final bool usedFallback;
}
