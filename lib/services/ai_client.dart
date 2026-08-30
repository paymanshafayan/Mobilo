import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/ai_settings.dart';

/// Error with a user-presentable (Persian) message.
class AiApiException implements Exception {
  const AiApiException(this.statusCode, this.message);

  /// HTTP status (0 = network-level failure).
  final int statusCode;
  final String message;

  @override
  String toString() => 'AiApiException($statusCode): $message';
}

/// Lets the UI abort an in-flight streaming request.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get cancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Incremental parser for Server-Sent-Events `data:` payloads.
///
/// OpenAI-compatible chat completions with `stream: true` send:
/// ```
/// data: {"choices":[{"delta":{"content":"Hello"}}]}
///
/// data: [DONE]
/// ```
/// Chunks from the socket may split lines arbitrarily, so [feed] buffers
/// until a full line arrives.
class SseLineParser {
  final StringBuffer _pending = StringBuffer();

  /// Feeds one raw chunk; returns the data payloads whose SSE event
  /// (terminated by a blank line) has fully arrived — without the `data:`
  /// prefix and excluding `[DONE]`. Data lines from an in-flight event
  /// stay buffered until the event's blank line arrives, so chunks may be
  /// split anywhere (mid-line, mid-payload, mid-event).
  List<String> feed(String chunk) {
    _pending.write(chunk);
    final text = _pending.toString();
    final lines = text.split('\n');
    final complete = lines.sublist(0, lines.length - 1);
    final partialLine = lines.last;

    // Everything after the last blank line belongs to an in-flight event.
    var flushUpTo = complete.length;
    for (var i = complete.length - 1; i >= 0; i--) {
      if (complete[i].trim().isEmpty) break;
      flushUpTo = i;
    }

    // Re-buffer the in-flight event plus the partial trailing line.
    _pending
      ..clear()
      ..write(
          [...complete.sublist(flushUpTo), partialLine]
              .where((l) => l.isNotEmpty)
              .join('\n'));

    final payloads = <String>[];
    for (final line in complete.sublist(0, flushUpTo)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isNotEmpty && payload != '[DONE]') {
        payloads.add(payload);
      }
    }
    return payloads;
  }
}

/// Minimal OpenAI-compatible chat completions client (no vendor SDK).
///
/// Uses `dart:io` directly so the app has zero extra HTTP dependencies.
class AiClient {
  const AiClient();

  String _chatUrl(AiProviderDef provider) => '${provider.baseUrl}/chat/completions';

  /// Starts a streaming chat completion; yields assistant text chunks.
  Future<Stream<String>> chatStream({
    required AiProviderDef provider,
    required String model,
    required List<Map<String, String>> messages,
    CancelToken? token,
    Map<String, dynamic>? extra,
  }) async {
    final controller = StreamController<String>();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final parser = SseLineParser();

    Future<void> run() async {
      try {
        final request = await client.postUrl(Uri.parse(_chatUrl(provider)));
        request.headers.set('authorization', 'Bearer ${provider.effectiveKey}');
        request.headers.set('content-type', 'application/json');
        request.headers.set('accept', 'text/event-stream');
        request.write(jsonEncode(<String, dynamic>{
          'model': model,
          'messages': messages,
          'stream': true,
          if (extra != null) ...extra,
        }));
        final response = await request.close();
        if (response.statusCode != 200) {
          final raw = await response.transform(const Utf8Decoder()).join();
          if (!controller.isClosed) {
            controller
              ..addError(AiApiException(response.statusCode,
                  _friendlyError(response.statusCode, raw)))
              ..close();
          }
          return;
        }
        late final StreamSubscription<List<int>> sub;
        sub = response.listen(
          (bytes) {
            if (token != null && token.cancelled) return;
            for (final payload
                in parser.feed(utf8.decode(bytes, allowMalformed: true))) {
              final piece = deltaContent(payload);
              if (piece != null && !controller.isClosed) {
                controller.add(piece);
              }
            }
          },
          onError: (Object error) {
            if (!controller.isClosed) controller.addError(error);
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
        if (token != null) {
          unawaited(token.whenCancelled.then((_) async {
            try {
              await sub.cancel();
            } catch (_) {}
            try {
              final socket = await response.detachSocket();
              socket.destroy();
            } catch (_) {}
            if (!controller.isClosed) await controller.close();
          }));
        }
      } on AiApiException catch (e) {
        if (!controller.isClosed) {
          controller
            ..addError(e)
            ..close();
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller
            ..addError(AiApiException(0, 'اتصال برقرار نشد. دوباره تلاش کنید.'))
            ..close();
        }
      } finally {
        client.close(force: true);
      }
    }

    unawaited(run());
    return controller.stream;
  }

  /// Non-streaming completion (used by the web-search section).
  ///
  /// [jsonMode] asks the provider for strict JSON output (only sent to
  /// Groq; other OpenAI-compatible providers get the JSON instruction in
  /// the prompt and the reply is parsed leniently).
  Future<String> complete({
    required AiProviderDef provider,
    required String model,
    required List<Map<String, String>> messages,
    Map<String, dynamic>? extra,
    bool jsonMode = false,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(Uri.parse(_chatUrl(provider)));
      request.headers.set('authorization', 'Bearer ${provider.effectiveKey}');
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode(<String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': false,
        if (jsonMode && provider.id == 'groq')
          'response_format': {'type': 'json_object'},
        if (extra != null) ...extra,
      }));
      final response = await request.close().timeout(timeout);
      final raw = await response.transform(const Utf8Decoder()).join();
      if (response.statusCode != 200) {
        throw AiApiException(
            response.statusCode, _friendlyError(response.statusCode, raw));
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final message = choices.first['message'];
          if (message is Map<String, dynamic>) {
            final content = message['content'];
            if (content is String) return content;
          }
        }
      }
      throw const AiApiException(500, 'پاسخ نامعتبر از سرویس دریافت شد.');
    } on AiApiException {
      rethrow;
    } on SocketException {
      throw const AiApiException(0, 'اتصال برقرار نشد. شبکه را بررسی کنید.');
    } catch (e) {
      throw AiApiException(0, 'خطا در ارتباط با سرویس: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Extracts `choices[0].delta.content` from one SSE payload (null-safe).
  ///
  /// Public for unit tests.
  static String? deltaContent(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final delta = choices.first['delta'];
      if (delta is! Map<String, dynamic>) return null;
      final content = delta['content'];
      return content is String ? content : null;
    } catch (_) {
      return null;
    }
  }

  static String _friendlyError(int status, String raw) {
    String providerMsg = '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map<String, dynamic> && err['message'] is String) {
          providerMsg = err['message'] as String;
        }
      }
    } catch (_) {}
    final base = switch (status) {
      401 => 'کلید API نامعتبر است؛ آن را در تنظیمات > مدل بررسی کنید.',
      403 => 'دسترسی با این کلید مجاز نیست.',
      404 => 'مدل یا سرویس یافت نشد؛ نام مدل را در تنظیمات بررسی کنید.',
      429 => 'سهمیهٔ درخواست‌ها تمام شده؛ کمی صبر کنید و دوباره تلاش کنید.',
      _ => 'خطای سرویس (کد $status).',
    };
    return providerMsg.isEmpty ? base : '$base ($providerMsg)';
  }
}

/// The web-search section: routes the user's query through the configured
/// search provider/model (default: Groq `groq/compound`, whose built-in
/// web-search tool answers with citations from live web pages).
class WebSearchService {
  static const String _systemPrompt = '''
You are the web search assistant inside the Mobilo app.
Search the live web for the user's query and answer in the same language the user wrote (usually Persian/Farsi).
Keep the answer concise and factual.
At the end, list the source URLs you used, one per line, as plain URLs without markdown formatting.
If you find direct download links for files relevant to the request, include the full URLs in your answer.
''';

  const WebSearchService();

  Future<String> search(AiSettings settings, String query) async {
    final provider = settings.providerFor(AiSettings.sectionWebSearch);
    final model = settings.modelFor(AiSettings.sectionWebSearch);

    Map<String, dynamic>? extra;
    if (provider.id == 'groq') {
      // Explicitly enable the built-in web search tool (Groq compound).
      extra = {
        'compound_custom': {
          'tools': {'enabled_tools': ['web_search']}
        }
      };
    }

    return const AiClient().complete(
      provider: provider,
      model: model,
      messages: [
        const {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': query},
      ],
      extra: extra,
    );
  }
}

/// System prompt for the chat section.
///
/// `/no_think` disables Qwen3's internal reasoning (faster, cheaper) -
/// ignored harmlessly by other models.
const String chatSystemPrompt = '''
/no_think
You are Mobina (مبینا), the helpful assistant inside the Mobilo app (an Android/iOS app that monitors battery level and alerts the user).
Reply in the user's language; default to Persian (Farsi).
Be short, practical and friendly.
If you find direct download links for files relevant to the request, include the full URLs in your answer.
''';
