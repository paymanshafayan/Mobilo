import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/ai_settings.dart';
import '../core/fa.dart';
import 'ai_client.dart';
import 'contacts_service.dart';
import 'download_service.dart';
import 'guard_channel.dart';

/// System prompt for Mobina's spoken answers.
///
/// `/no_think` disables Qwen3's internal reasoning (faster replies);
/// ignored harmlessly by other models.
const String mobinaSystemPrompt = '''
/no_think
You are Mobina (مبینا), the friendly voice assistant inside the Mobilo app (an Android/iOS battery guardian app).
Your answers are read aloud to the user, so speak naturally and keep them short (1-3 sentences), without markdown, tables, code or raw URLs.
Reply in the user's language; default to Persian (Farsi).
''';

/// System prompt for classifying a voice command into a JSON intent.
/// (Must contain the word "JSON" and the schema, per Groq's json_object mode.)
const String mobinaIntentPrompt = '''
/no_think
You are Mobina (مبینا), the voice assistant of the Mobilo app.
Classify the user's voice command and respond with ONLY a JSON object (no other text).
Schema:
{"action": "call_contact" | "search_web" | "download_file" | "chat", "target": string or null, "query": string or null, "url": string or null}
Rules:
- "call_contact": the user wants to find and call a contact; target = the contact name as spoken (e.g. "مامان").
- "search_web": the user wants a web search; query = the search phrase.
- "download_file": the user wants a file downloaded; url = the file URL if mentioned, otherwise null.
- "chat": anything else (questions, small talk, battery advice).
Keep string values in the user's language (Persian), except URLs.
''';

/// One line of the Mobina conversation, broadcast to the UI.
class MobinaEvent {
  const MobinaEvent({
    required this.isUser,
    required this.text,
    this.isSearch = false,
  });

  final bool isUser;
  final String text;
  final bool isSearch;
}

enum MobinaPhase { idle, listening, capturing, thinking, speaking }

/// A voice command as classified by the AI.
class MobinaIntent {
  const MobinaIntent({
    required this.action,
    this.target,
    this.query,
    this.url,
  });

  static const List<String> actions = [
    'call_contact',
    'search_web',
    'download_file',
    'chat',
  ];

  final String action;
  final String? target;
  final String? query;
  final String? url;

  /// Lenient parser: finds the first JSON object in [raw] (models may add
  /// chatter around it on non-Groq providers).
  static MobinaIntent parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return const MobinaIntent(action: 'chat');
    }
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) {
        return const MobinaIntent(action: 'chat');
      }
      final action = decoded['action'] as String? ?? 'chat';
      return MobinaIntent(
        action: actions.contains(action) ? action : 'chat',
        target: decoded['target'] as String?,
        query: decoded['query'] as String?,
        url: decoded['url'] as String?,
      );
    } catch (_) {
      return const MobinaIntent(action: 'chat');
    }
  }
}

/// Wake-word variants (Persian as the recognizer may spell them + Latin).
const List<String> _wakeWordPatterns = ['مبینا', 'مبینا', 'mobina'];

/// Returns the text spoken AFTER the wake word, or null when the wake
/// word is not present. Null with empty after == "wake word only".
String? textAfterWakeWord(String text) {
  final lower = text.toLowerCase();
  int? bestIndex;
  String? bestPattern;
  for (final p in _wakeWordPatterns) {
    final i = lower.indexOf(p);
    if (i >= 0 && (bestIndex == null || i < bestIndex)) {
      bestIndex = i;
      bestPattern = p;
    }
  }
  if (bestIndex == null || bestPattern == null) return null;
  return text.substring(bestIndex + bestPattern.length);
}

/// Prepares an AI answer for text-to-speech: strips URLs/markdown, trims to
/// a sentence boundary (TTS should not read 40 lines aloud).
String ttsReadyText(String text) {
  var t = text
      .replaceAll(RegExp(r'https?://\S+'), ' ')
      .replaceAll(RegExp(r'[*_`>#|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.length > 450) {
    final cut = t.substring(0, 450);
    var idx = -1;
    for (final sep in const [' . ', ' ! ', '؟ ', '. ']) {
      final i = cut.lastIndexOf(sep);
      if (i > idx) idx = i;
    }
    t = idx > 120 ? cut.substring(0, idx + 1) : cut;
  }
  return t.trim();
}

/// Mobina (مبینا): the app's always-listening voice assistant.
///
/// - Wake word: while armed, Mobina listens for «مبینا». On Android this
///   runs in a native foreground service (works with the app closed); on
///   iOS it runs in Dart while the app is open (Apple forbids background
///   microphone access).
/// - Commands: the spoken command is classified by the AI into a JSON
///   intent (call_contact / search_web / download_file / chat) and
///   executed, with the result spoken aloud.
/// - Live voice chat: a Gemini-style loop (listen -> AI -> speak -> listen)
///   shown in [VoiceChatSheet].
class VoiceAssistant {
  VoiceAssistant._();

  static final VoiceAssistant instance = VoiceAssistant._();

  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AiClient _client = const AiClient();
  final ContactsService _contacts = const ContactsService();
  final DownloadService _downloads = const DownloadService();
  final WebSearchService _search = const WebSearchService();

  static const MethodChannel _nativeChannel =
      MethodChannel('mobilo/voice_assistant');

  final StreamController<MobinaEvent> _events =
      StreamController<MobinaEvent>.broadcast();
  final List<MobinaEvent> recentEvents = [];

  Stream<MobinaEvent> get events => _events.stream;

  final ValueNotifier<MobinaPhase> phase = ValueNotifier(MobinaPhase.idle);
  final ValueNotifier<String> transcript = ValueNotifier('');
  final ValueNotifier<String> reply = ValueNotifier('');

  /// True while Mobina is armed (listening engine: native FGS or Dart).
  final ValueNotifier<bool> wakeEnabled = ValueNotifier(false);

  AiSettings? _settings;
  bool _sttReady = false;
  bool _ttsReady = false;
  bool _loopRunning = false;
  bool _liveChat = false;
  bool _executing = false;
  bool _speaking = false;
  Completer<void>? _speakDone;
  bool _nativeActive = false;

  // Wake-loop scratch state (written by callbacks, read by the loop).
  bool _needCapture = false;
  String? _capturedCommand;
  bool _wakeDetected = false;
  String? _wakeCommand;
  String _lastFinalText = '';

  CancelToken? _liveToken;
  String? _liveUtterance;
  final List<Map<String, String>> _liveHistory = [];

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Arms Mobina. Called once from main().
  Future<void> start() async {
    await _initNative();
    _settings = await AiSettings.load();
    await _armFromSettings();
  }

  /// Re-arms after the user changes voice settings.
  Future<void> refresh() async {
    _stopDartLoop();
    if (GuardChannel.instance.isAndroid) {
      await _nativeStop();
    }
    _nativeActive = false;
    _settings = await AiSettings.load();
    await _armFromSettings();
  }

  Future<void> _armFromSettings() async {
    final enabled = _settings?.wakeWordEnabled ?? false;
    wakeEnabled.value = enabled;
    if (!enabled || _liveChat) return;
    if (GuardChannel.instance.isAndroid) {
      // Initialize STT first: on Android this triggers the microphone
      // permission dialog, which the native wake service needs too.
      if (!_sttReady) {
        try {
          _sttReady = await _stt.initialize(onError: (_) {});
        } catch (_) {
          _sttReady = false;
        }
      }
      await _nativeStart();
      // The service reports back via 'status'; if it never does (or says it
      // has no recognizer) fall back to the Dart loop.
      await Future<void>.delayed(const Duration(milliseconds: 3000));
      if (!_nativeActive) _startDartLoop();
    } else {
      _startDartLoop();
    }
  }

  Future<void> _initNative() async {
    if (!GuardChannel.instance.isAndroid) return;
    _nativeChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'status':
          final ok = (call.arguments as Map?)?['ok'] as bool? ?? false;
          _nativeActive = ok;
          if (ok) {
            _stopDartLoop(); // the service owns the microphone now
          } else if (_settings?.wakeWordEnabled ?? false) {
            _startDartLoop(); // no recognizer -> Dart fallback
          }
        case 'command':
          final text = (call.arguments as Map?)?['text'] as String? ?? '';
          if (text.trim().isNotEmpty && !_liveChat && !_executing) {
            unawaited(_handleCommand(text.trim()));
          }
      }
    });
  }

  Future<void> _nativeStart() async {
    try {
      await _nativeChannel.invokeMethod('start');
    } catch (_) {}
  }

  Future<void> _nativeStop() async {
    _nativeActive = false;
    try {
      await _nativeChannel.invokeMethod('stop');
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Dart wake loop (iOS + Android fallback)
  // ------------------------------------------------------------------

  void _startDartLoop() {
    if (_loopRunning || _liveChat) return;
    _loopRunning = true;
    wakeEnabled.value = true;
    if (phase.value == MobinaPhase.idle) {
      phase.value = MobinaPhase.listening;
    }
    unawaited(_loop());
  }

  void _stopDartLoop() {
    if (!_loopRunning) return;
    _loopRunning = false;
    _needCapture = false;
    _capturedCommand = null;
    _wakeDetected = false;
    _wakeCommand = null;
    _stt.stop();
    if (phase.value != MobinaPhase.idle && !_liveChat) {
      phase.value = MobinaPhase.idle;
    }
    wakeEnabled.value = false;
  }

  Future<void> _loop() async {
    while (_loopRunning) {
      await _awaitIdle();
      if (!_loopRunning) break;
      if (!_sttReady) {
        try {
          _sttReady = await _stt.initialize(onError: (_) {});
        } catch (_) {
          _sttReady = false;
        }
        if (!_sttReady) {
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
      }
      _wakeDetected = false;
      _wakeCommand = null;
      _capturedCommand = null;
      _lastFinalText = '';
      try {
        await _stt.listen(
          onResult: _onWakeResult,
          listenOptions:
              stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
        );
      } catch (_) {}
      if (!_loopRunning) break;

      if (_capturedCommand != null) {
        final command = _capturedCommand!;
        _capturedCommand = null;
        _needCapture = false;
        phase.value = MobinaPhase.listening;
        unawaited(_handleCommand(command));
        continue;
      }
      if (_wakeDetected) {
        _wakeDetected = false;
        final after = _wakeCommand?.trim() ?? '';
        _wakeCommand = null;
        if (after.isNotEmpty) {
          _needCapture = false;
          phase.value = MobinaPhase.listening;
          unawaited(_handleCommand(after));
        } else {
          _needCapture = true;
          phase.value = MobinaPhase.capturing;
          if (!GuardChannel.instance.isAndroid) {
            // iOS: announce audibly that Mobina is listening for the command.
            unawaited(_speak('بفرمایید'));
          }
        }
        continue;
      }
      if (_needCapture && _lastFinalText.trim().isEmpty) {
        // Capture timed out: the user said nothing after the wake word.
        _needCapture = false;
        phase.value = MobinaPhase.listening;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  void _onWakeResult(SpeechRecognitionResult result) {
    if (_liveChat) return; // the live session has its own callback
    final words = result.recognizedWords.trim();
    if (_needCapture) {
      if (result.finalResult) {
        _lastFinalText = words;
        if (words.isNotEmpty) _capturedCommand = words;
      } else {
        transcript.value = words;
      }
      return;
    }
    transcript.value = words;
    final after = words.isEmpty ? null : textAfterWakeWord(words);
    if (after != null) {
      _wakeDetected = true;
      if (_wakeCommand == null || after.length > _wakeCommand!.length) {
        _wakeCommand = after;
      }
    }
  }

  // ------------------------------------------------------------------
  // Command execution
  // ------------------------------------------------------------------

  Future<void> _handleCommand(String command) async {
    if (_executing) return;
    _executing = true;
    phase.value = MobinaPhase.thinking;
    transcript.value = command;
    _emit(MobinaEvent(isUser: true, text: command));
    try {
      final settings = await AiSettings.load();
      _settings = settings;
      final provider = settings.providerFor(AiSettings.sectionChat);
      final model = settings.modelFor(AiSettings.sectionChat);

      MobinaIntent intent;
      try {
        final raw = await _client.complete(
          provider: provider,
          model: model,
          jsonMode: true,
          messages: [
            {'role': 'system', 'content': mobinaIntentPrompt},
            {'role': 'user', 'content': command},
          ],
        );
        intent = MobinaIntent.parse(raw);
      } catch (e) {
        // Classification failed: answer the command directly as chat.
        intent = const MobinaIntent(action: 'chat');
        final msg = e is AiApiException
            ? e.message
            : 'خطا در فهم درخواست: $e';
        _emit(MobinaEvent(isUser: false, text: msg));
        await _speak(msg);
        return;
      }

      switch (intent.action) {
        case 'call_contact':
          await _callContact(settings, intent);
        case 'search_web':
          await _webSearch(settings, intent, command);
        case 'download_file':
          await _downloadFile(intent);
        default:
          await _plainChat(settings, provider, model, command);
      }
    } finally {
      _executing = false;
      if (_loopRunning && !_liveChat) {
        phase.value =
            _needCapture ? MobinaPhase.capturing : MobinaPhase.listening;
      } else if (!_liveChat) {
        phase.value = MobinaPhase.idle;
      }
    }
  }

  Future<void> _callContact(AiSettings settings, MobinaIntent intent) async {
    final target = (intent.target ?? '').trim();
    if (target.isEmpty) {
      final msg = 'چه مخاطبی را می‌خواهید؟';
      _emit(MobinaEvent(isUser: false, text: msg));
      await _speak(msg);
      return;
    }
    final ok = await _contacts.ensurePermission();
    if (!ok) {
      final msg = 'برای خواندن مخاطبین، مجوز مخاطبین را در تنظیمات فعال کنید.';
      _emit(MobinaEvent(isUser: false, text: msg));
      await _speak(msg);
      return;
    }
    List<ContactSummary> contacts;
    try {
      contacts = await _contacts.list();
    } catch (_) {
      final msg = 'خواندن مخاطبین ممکن نشد.';
      _emit(MobinaEvent(isUser: false, text: msg));
      await _speak(msg);
      return;
    }
    final found = _contacts.lookup(contacts, target);
    if (found == null) {
      final msg = 'متأسفانه مخاطبی با نام «$target» پیدا نشد.';
      _emit(MobinaEvent(isUser: false, text: msg));
      await _speak(msg);
      return;
    }
    final msg =
        'شماره‌ی ${found.name}: ${faDigits(found.number)}. در حال گرفتن است.';
    _emit(MobinaEvent(isUser: false, text: msg));
    await _speak(msg);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    try {
      await _contacts.dial(found.number);
    } catch (_) {}
  }

  Future<void> _webSearch(
      AiSettings settings, MobinaIntent intent, String command) async {
    final query = (intent.query ?? '').trim().isEmpty ? command : intent.query!.trim();
    _emit(MobinaEvent(isUser: false, text: '🌐 در حال جستجو: $query'));
    final answer = await _search.search(settings, query);
    _emit(MobinaEvent(isUser: false, text: answer, isSearch: true));
    await _speak(answer);
  }

  Future<void> _downloadFile(MobinaIntent intent) async {
    String? url = intent.url?.trim();
    if (url == null || url.isEmpty) {
      final urls = extractFileUrls(intent.target ?? intent.query ?? '');
      url = urls.isNotEmpty ? urls.first : null;
    }
    if (url == null) {
      final msg = 'آدرس فایلی برای دانلود ندادید.';
      _emit(MobinaEvent(isUser: false, text: msg));
      await _speak(msg);
      return;
    }
    final result = await _downloads.download(url: url);
    final msg = 'دانلود شد: ${result.fileName} (${result.sizeLabel}).';
    _emit(MobinaEvent(isUser: false, text: msg));
    await _speak(msg);
  }

  Future<void> _plainChat(AiSettings settings, AiProviderDef provider,
      String model, String command) async {
    final answer = await _client.complete(
      provider: provider,
      model: model,
      messages: [
        {'role': 'system', 'content': mobinaSystemPrompt},
        {'role': 'user', 'content': command},
      ],
    );
    _emit(MobinaEvent(isUser: false, text: answer));
    await _speak(answer);
  }

  void _emit(MobinaEvent e) {
    recentEvents.add(e);
    if (recentEvents.length > 40) {
      recentEvents.removeRange(0, recentEvents.length - 40);
    }
    _events.add(e);
  }

  // ------------------------------------------------------------------
  // Live voice chat (Gemini-style)
  // ------------------------------------------------------------------

  /// Temporarily pauses the wake listeners so the chat screen's own
  /// dictation mic does not fight for the microphone.
  Future<void> suspendForChatMic() async {
    _stopDartLoop();
    if (GuardChannel.instance.isAndroid) {
      await _nativeStop();
    }
  }

  /// Restores the wake listeners after the chat mic session ends.
  Future<void> resumeAfterChatMic() async {
    if (_liveChat) return;
    final armed = _settings?.wakeWordEnabled ?? false;
    if (!armed) return;
    if (GuardChannel.instance.isAndroid) {
      await _nativeStart();
      await Future<void>.delayed(const Duration(milliseconds: 3000));
      if (!_nativeActive) _startDartLoop();
    } else if (!_loopRunning) {
      _startDartLoop();
    }
  }

  Future<void> startLiveChat() async {
    if (_liveChat) return;
    _stopDartLoop(); // one listener at a time
    if (GuardChannel.instance.isAndroid) {
      await _nativeStop(); // the FGS would fight for the mic
    }
    _liveChat = true;
    _liveHistory.clear();
    transcript.value = '';
    reply.value = '';
    phase.value = MobinaPhase.listening;
    unawaited(_liveLoop());
  }

  void stopLiveChat() {
    if (!_liveChat) return;
    _liveChat = false;
    _liveToken?.cancel();
    _stt.stop();
    _tts.stop();
    _completeSpeak();
    transcript.value = '';
    reply.value = '';
    phase.value = MobinaPhase.idle;
    // Re-arm the wake listener if Mobina should be armed.
    if (_settings?.wakeWordEnabled ?? false) {
      if (GuardChannel.instance.isAndroid) {
        unawaited(_rearmNative());
      } else if (!_loopRunning) {
        _startDartLoop();
      }
    }
  }

  Future<void> _rearmNative() async {
    await _nativeStart();
    await Future<void>.delayed(const Duration(milliseconds: 3000));
    if (!_nativeActive) _startDartLoop();
  }

  Future<void> _liveLoop() async {
    while (_liveChat) {
      await _awaitIdle();
      if (!_liveChat) break;
      if (!_sttReady) {
        try {
          _sttReady = await _stt.initialize(onError: (_) {});
        } catch (_) {
          _sttReady = false;
        }
        if (!_sttReady) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      }
      phase.value = MobinaPhase.listening;
      _liveUtterance = null;
      transcript.value = '';
      try {
        await _stt.listen(
          onResult: (SpeechRecognitionResult r) {
            if (!_liveChat) return;
            transcript.value = r.recognizedWords;
            if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
              _liveUtterance = r.recognizedWords.trim();
            }
          },
          listenOptions:
              stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
        );
      } catch (_) {}
      if (!_liveChat) break;
      final utterance = _liveUtterance;
      if (utterance == null) continue; // silence/timeout: listen again

      _emit(MobinaEvent(isUser: true, text: utterance));
      _liveHistory
          .add({'role': 'user', 'content': utterance});
      phase.value = MobinaPhase.thinking;
      reply.value = '';

      var full = '';
      try {
        final settings = await AiSettings.load();
        _settings = settings;
        final recent = _liveHistory.length > 20
            ? _liveHistory.sublist(_liveHistory.length - 20)
            : _liveHistory;
        final messages = <Map<String, String>>[
          {'role': 'system', 'content': mobinaSystemPrompt},
          ...recent,
        ];
        _liveToken = CancelToken();
        final stream = await _client.chatStream(
          provider: settings.providerFor(AiSettings.sectionChat),
          model: settings.modelFor(AiSettings.sectionChat),
          messages: messages,
          token: _liveToken,
        );
        await for (final piece in stream) {
          if (!_liveChat) break;
          full += piece;
          reply.value = full;
        }
      } catch (e) {
        full = e is AiApiException ? e.message : 'خطا: $e';
      }
      if (!_liveChat) break;
      if (full.isNotEmpty) {
        _liveHistory.add({'role': 'assistant', 'content': full});
        _emit(MobinaEvent(isUser: false, text: full));
      }
      // Speak the reply, then the loop goes back to listening (turn-taking).
      await _speak(full);
    }
    if (!_liveChat) {
      transcript.value = '';
      phase.value = MobinaPhase.idle;
    }
  }

  // ------------------------------------------------------------------
  // Speech output (TTS) with completion gate
  // ------------------------------------------------------------------

  Future<void> _speak(String text) async {
    final settings = _settings ?? AiSettings.defaults();
    // The wake chime always plays; normal replies respect the TTS toggle.
    final allowed = settings.voiceTtsEnabled || text == 'بفرمایید';
    if (!allowed) return;
    final say = ttsReadyText(text);
    if (say.trim().isEmpty) return;
    await _ensureTts();
    _speaking = true;
    _speakDone = Completer<void>();
    phase.value = MobinaPhase.speaking;
    try {
      await _tts.speak(say);
      await _speakDone!
          .future
          .timeout(const Duration(seconds: 90), onTimeout: () {});
    } catch (_) {}
    _speaking = false;
    _speakDone = null;
    if (_liveChat) {
      // the live loop restores the phase
    } else if (_loopRunning) {
      phase.value =
          _needCapture ? MobinaPhase.capturing : MobinaPhase.listening;
    }
  }

  void _completeSpeak() {
    if (_speaking && _speakDone != null && !_speakDone!.isCompleted) {
      _speakDone!.complete();
    }
  }

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    try {
      await _tts.setLanguage('fa-IR');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      _tts.setCompletionHandler(_completeSpeak);
      _tts.setCancelHandler(_completeSpeak);
      _ttsReady = true;
    } catch (_) {}
  }

  Future<void> _awaitIdle() async {
    while (_speaking) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
