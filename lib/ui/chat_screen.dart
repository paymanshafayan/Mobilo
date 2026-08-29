import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../core/ai_settings.dart';
import '../core/fa.dart';
import '../services/ai_client.dart';
import '../services/download_service.dart';

class _ChatMsg {
  _ChatMsg({required this.isUser, this.text = '', this.error = ''});

  final bool isUser;
  String text;
  String error;

  bool get hasError => error.isNotEmpty;
}

/// Gemini/ChatGPT-style AI assistant: text + voice input, streaming replies,
/// web-search mode, tappable citation links, file download chips and
/// read-aloud (TTS) for replies.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AiClient _client = AiClient();
  final DownloadService _downloads = const DownloadService();
  final WebSearchService _search = const WebSearchService();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_ChatMsg> _messages = [];
  bool _busy = false;
  bool _streaming = false;
  bool _searchMode = false;
  bool _listening = false;
  bool _sttReady = false;
  bool _ttsReady = false;
  int _speakingIndex = -1;
  String _liveWords = '';
  String _modelLabel = 'Mobilo AI';
  CancelToken? _token;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stopGeneration();
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    _tts.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Sending / generation
  // ------------------------------------------------------------------

  Future<void> _send({String? preset}) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    FocusScope.of(context).unfocus();

    _messages.add(_ChatMsg(isUser: true, text: text));
    final placeholder = _ChatMsg(isUser: false);
    _messages.add(placeholder);
    setState(() => _busy = true);
    _scrollToBottom();

    final settings = await AiSettings.load();
    if (!mounted) return;
    final chatModel = settings.modelFor(AiSettings.sectionChat);
    final searchModel = settings.modelFor(AiSettings.sectionWebSearch);
    _modelLabel = _searchMode ? '🌐 $searchModel' : chatModel;
    if (mounted) setState(() {});

    try {
      if (_searchMode) {
        final answer = await _search.search(settings, text);
        placeholder.text = answer;
        _busy = false;
      } else {
        _streaming = true;
        _token = CancelToken();
        final stream = await _client.chatStream(
          provider: settings.providerFor(AiSettings.sectionChat),
          model: settings.modelFor(AiSettings.sectionChat),
          messages: _historyForApi(),
          token: _token,
        );
        _sub = stream.listen(
          (piece) {
            if (!mounted) return;
            placeholder.text += piece;
            setState(() {});
            _scrollToBottom();
          },
          onError: (Object e) {
            placeholder.error = _humanError(e);
          },
          onDone: () {
            _streaming = false;
            _busy = false;
            _token = null;
            _sub = null;
            if (mounted) {
              setState(() {});
              _scrollToBottom();
            }
          },
        );
        return; // streaming: _busy is cleared in onDone
      }
    } catch (e) {
      placeholder.error = _humanError(e);
      _busy = false;
    }
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _stopGeneration() {
    _token?.cancel();
    _sub?.cancel();
    _streaming = false;
    _busy = false;
    _token = null;
    _sub = null;
    if (mounted) setState(() {});
  }

  List<Map<String, String>> _historyForApi() {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': chatSystemPrompt},
    ];
    final recent =
        _messages.where((m) => !m.hasError && m.text.isNotEmpty).take(20).toList();
    for (final m in recent) {
      messages.add(
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text});
    }
    return messages;
  }

  String _humanError(Object e) {
    if (e is AiApiException) return e.message;
    return 'خطا: $e';
  }

  // ------------------------------------------------------------------
  // Voice input (STT)
  // ------------------------------------------------------------------

  Future<void> _toggleMic() async {
    if (_listening) {
      await _stt.stop();
      _listening = false;
      if (mounted) setState(() {});
      return;
    }
    if (!_sttReady) {
      final ok = await _stt.initialize(onError: (e) {
        if (mounted) _snack(e.errorMsg);
      });
      if (!mounted) return;
      _sttReady = ok;
      if (!ok) {
        _snack(Strings.micUnavailable);
        return;
      }
    }
    _liveWords = '';
    _listening = true;
    if (mounted) setState(() {});
    await _stt.listen(onResult: (stt.SpeechRecognitionResult result) {
      if (result.finalResult) {
        final words = result.recognizedWords;
        if (words.isNotEmpty) {
          _input.text = '${_input.text} $words'.trim();
        }
        _listening = false;
      } else {
        _liveWords = result.recognizedWords;
      }
      if (mounted) setState(() {});
    });
  }

  // ------------------------------------------------------------------
  // Voice output (TTS)
  // ------------------------------------------------------------------

  Future<void> _toggleSpeak(int index) async {
    if (_speakingIndex == index) {
      await _tts.stop();
      _speakingIndex = -1;
      if (mounted) setState(() {});
      return;
    }
    try {
      if (!_ttsReady) {
        await _tts.setLanguage('fa-IR');
        await _tts.setSpeechRate(0.5);
        await _tts.setVolume(1.0);
        _ttsReady = true;
      }
      await _tts.stop();
      await _tts.speak(_messages[index].text);
      _speakingIndex = index;
      if (mounted) setState(() {});
    } catch (e) {
      _snack('${Strings.ttsError}: $e');
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  void _clearChat() {
    _stopGeneration();
    _messages.clear();
    _speakingIndex = -1;
    setState(() {});
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Strings.chatTitle),
            Text(
              _currentModelLabel(),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: Strings.chatNew,
            icon: const Icon(Icons.restart_alt),
            onPressed: _busy ? null : _clearChat,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _bubble(context, i,
                          scheme, isLastBusy: i == _messages.length - 1),
                    ),
            ),
            if (_listening)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: scheme.errorContainer,
                child: Row(
                  children: [
                    const Icon(Icons.mic, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _liveWords.isEmpty
                            ? Strings.micListening
                            : _liveWords,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onErrorContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            _inputBar(scheme),
          ],
        ),
      ),
    );
  }

  String _currentModelLabel() => _modelLabel;

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.smart_toy, size: 64, color: scheme.primary),
        const SizedBox(height: 12),
        Text(
          Strings.chatWelcome,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          Strings.chatWelcomeSub,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final s in [
              Strings.suggestBatteryTips,
              Strings.suggestSearch,
            ])
              ActionChip(
                avatar: Icon(_searchMode
                    ? Icons.public
                    : Icons.lightbulb_outline,
                    size: 18),
                label: Text(s),
                onPressed: () => _send(preset: s),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bubble(
      BuildContext context, int index, ColorScheme scheme,
      {required bool isLastBusy}) {
    final msg = _messages[index];
    final isUser = msg.isUser;
    final isPlaceholderBusy =
        isLastBusy && !isUser && _busy && msg.text.isEmpty && !msg.hasError;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isUser
                ? scheme.primaryContainer
                : scheme.secondaryContainer,
            child: Icon(
              isUser ? Icons.person : Icons.smart_toy,
              size: 16,
              color: isUser
                  ? scheme.onPrimaryContainer
                  : scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.hasError)
                    Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(msg.error,
                              style: TextStyle(
                                  color: scheme.error, fontSize: 13)),
                        ),
                      ],
                    )
                  else if (isPlaceholderBusy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: scheme.primary),
                      ),
                    )
                  else ...[
                    if (isUser)
                      Text(msg.text,
                          style: TextStyle(
                              color: scheme.onSurface, fontSize: 15,
                              height: 1.45))
                    else
                      _linkText(context, msg.text, scheme),
                    ..._fileTiles(msg.text, isUser),
                  ],
                  if (!isUser && !msg.hasError && msg.text.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: Strings.speakReply,
                          icon: Icon(
                            _speakingIndex == index
                                ? Icons.stop
                                : Icons.volume_up,
                            size: 16,
                            color: _speakingIndex == index
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                          onPressed: () => _toggleSpeak(index),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders text with tappable http(s) links (citations / file URLs).
  Widget _linkText(BuildContext context, String text, ColorScheme scheme) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'''https?://[^\s)"']+''', caseSensitive: false);
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          fontSize: 13,
        ),
        recognizer: _TapUrl(url),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return RichText(
      text: TextSpan(
        children: spans,
        style: TextStyle(color: scheme.onSurface, fontSize: 15, height: 1.5),
      ),
      textAlign: TextAlign.right,
    );
  }

  List<Widget> _fileTiles(String text, bool isUser) {
    if (isUser) return const [];
    final urls = extractFileUrls(text);
    return [
      for (final url in urls) _FileDownloadTile(url: url),
    ];
  }

  Widget _inputBar(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: Strings.chatSearchMode,
            onPressed: _busy ? null : () {
              _searchMode = !_searchMode;
              setState(() {});
            },
            icon: Icon(
              Icons.public,
              color: _searchMode ? scheme.primary : scheme.onSurfaceVariant,
            ),
            style: IconButton.styleFrom(
              backgroundColor:
                  _searchMode ? scheme.primaryContainer : Colors.transparent,
              shape: const CircleBorder(),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _input,
              maxLines: 1,
              minLines: 1,
              textInputAction: TextInputAction.send,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                hintText: _searchMode
                    ? Strings.chatSearchHint
                    : Strings.chatHint,
              ),
              onSubmitted: _busy ? null : (_) => _send(),
            ),
          ),
          IconButton(
            tooltip: Strings.micListening,
            onPressed: _busy ? null : _toggleMic,
            icon: Icon(
              _listening ? Icons.stop : Icons.mic,
              color: _listening ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: _busy ? Strings.chatStop : Strings.chatSend,
            onPressed: _busy
                ? (_streaming ? _stopGeneration : null)
                : () => _send(),
            icon: Icon(
              _busy && _streaming ? Icons.stop : Icons.arrow_upward,
              color: _busy
                  ? scheme.onSurfaceVariant
                  : (scheme.onPrimary),
            ),
            style: IconButton.styleFrom(
              backgroundColor: _busy
                  ? Colors.transparent
                  : scheme.primary,
              shape: const CircleBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a URL in the external browser.
class _TapUrl extends TapGestureRecognizer {
  _TapUrl(this.url);

  final String url;

  @override
  void handleTap() {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// A downloadable file chip: download with progress, then share/open.
class _FileDownloadTile extends StatefulWidget {
  const _FileDownloadTile({required this.url});

  final String url;

  @override
  State<_FileDownloadTile> createState() => _FileDownloadTileState();
}

class _FileDownloadTileState extends State<_FileDownloadTile> {
  final DownloadService _service = const DownloadService();

  double? _fraction;
  bool _active = false;
  bool _done = false;
  String? _path;
  String? _error;

  String get _name => fileNameFromUrl(widget.url);

  Future<void> _download() async {
    setState(() {
      _active = true;
      _error = null;
    });
    try {
      final result = await _service.download(
        url: widget.url,
        onProgress: (p) => setState(() => _fraction = p.fraction),
      );
      if (!mounted) return;
      setState(() {
        _path = result.path;
        _done = true;
        _active = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${Strings.fileDone}: ${result.fileName} (${result.sizeLabel})'),
          action: SnackBarAction(
            label: Strings.fileShare,
            onPressed: () => _service.share(result.path),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _active = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                if (_error != null)
                  Text(_error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.error)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_active)
            SizedBox(
              width: 70,
              child: LinearProgressIndicator(
                value: _fraction,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            )
          else if (_done)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 18, color: scheme.primary),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: Strings.fileShare,
                  icon: const Icon(Icons.ios_share, size: 18),
                  onPressed: _path == null ? null : () => _service.share(_path!),
                ),
              ],
            )
          else
            FilledButton.tonal(
              onPressed: _download,
              child: Text(Strings.fileDownload, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
