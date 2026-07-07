import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'system_prompt.dart';

/// Thrown when Groq returns HTTP 429 (rate limit). Surfaced to the UI with a
/// friendly message instead of triggering another request.
class GroqRateLimitException implements Exception {
  final int? retryAfterSeconds;
  GroqRateLimitException(this.retryAfterSeconds);
  @override
  String toString() => 'Rate limited';
}

class GroqService {
  static const _model = 'llama-3.1-8b-instant';
  static const _url = 'https://api.groq.com/openai/v1/chat/completions';

  final String apiKey;
  GroqService(this.apiKey);

  Future<List<Map<String, dynamic>>> parseMessage(
    String userMessage,
    List<Map<String, String>> chatHistory,
  ) async {
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // Keep token usage low (the free tier is tokens-per-minute limited): only
    // the last few turns are sent for context.
    final trimmedHistory = chatHistory.length > 4
        ? chatHistory.sublist(chatHistory.length - 4)
        : chatHistory;

    final response = await _post(userMessage, trimmedHistory, now, 0.1);

    if (response.statusCode == 429) {
      throw GroqRateLimitException(_retryAfter(response));
    }
    if (response.statusCode != 200) {
      throw Exception('Groq API error ${response.statusCode}: ${response.body}');
    }

    // Only retry on a malformed-JSON response — NOT on HTTP errors. Retrying a
    // rate-limited or failed request just burns more of the quota.
    try {
      return _extractIntents(response.body);
    } catch (_) {
      final retry = await _post(
        '$userMessage\n\nIMPORTANT: Respond with ONLY valid JSON in the format {"intents": [...]}',
        trimmedHistory,
        now,
        0.0,
      );
      if (retry.statusCode == 429) {
        throw GroqRateLimitException(_retryAfter(retry));
      }
      if (retry.statusCode != 200) {
        throw Exception('Groq API error ${retry.statusCode}: ${retry.body}');
      }
      return _extractIntents(retry.body);
    }
  }

  Future<http.Response> _post(
    String userMessage,
    List<Map<String, String>> chatHistory,
    String now,
    double temperature,
  ) {
    return http.post(
      Uri.parse(_url),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'temperature': temperature,
        'max_tokens': 500,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': buildSystemPrompt(now)},
          ...chatHistory,
          {'role': 'user', 'content': userMessage},
        ],
      }),
    );
  }

  List<Map<String, dynamic>> _extractIntents(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
    final raw = body['choices'][0]['message']['content'] as String;
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(parsed['intents'] as List);
  }

  int? _retryAfter(http.Response r) {
    final h = r.headers['retry-after'];
    if (h == null) return null;
    return int.tryParse(h.trim());
  }
}
