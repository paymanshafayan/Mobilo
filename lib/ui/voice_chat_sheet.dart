import 'package:flutter/material.dart';

import '../core/fa.dart';
import '../services/voice_assistant.dart';

/// Full-screen live voice conversation with Mobina, Gemini/ChatGPT style:
/// listen -> AI thinks -> Mobina speaks -> listen again (turn-taking).
class VoiceChatSheet extends StatefulWidget {
  const VoiceChatSheet({super.key});

  @override
  State<VoiceChatSheet> createState() => _VoiceChatSheetState();
}

class _VoiceChatSheetState extends State<VoiceChatSheet>
    with SingleTickerProviderStateMixin {
  final VoiceAssistant _assistant = VoiceAssistant.instance;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    unawaitedStart();
  }

  Future<void> unawaitedStart() async {
    // A microtask so the frame is up before the listener starts.
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      _assistant.startLiveChat();
    }
  }

  @override
  void dispose() {
    _assistant.stopLiveChat();
    _pulse.dispose();
    super.dispose();
  }

  void _close() {
    _assistant.stopLiveChat();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF07131F),
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer.withValues(alpha: 0.4),
                  child: Icon(Icons.smart_toy, color: Colors.white70),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'مبینا',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700),
                      ),
                      ValueListenableBuilder<MobinaPhase>(
                        valueListenable: _assistant.phase,
                        builder: (context, phase, _) => Text(
                          _phaseLabel(phase),
                          style: TextStyle(
                              color: Colors.white38, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: Strings.chatStop,
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: _close,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pulsing orb.
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final listening =
                          _assistant.phase.value == MobinaPhase.listening;
                      final active = _assistant.phase.value == MobinaPhase.thinking ||
                          _assistant.phase.value == MobinaPhase.speaking;
                      final scale =
                          1 + (listening || active ? _pulse.value * 0.12 : 0.0);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                scheme.primary.withValues(alpha: 0.85),
                                scheme.primary.withValues(alpha: 0.25),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.65, 1.0],
                            ),
                          ),
                          child: Container(
                            width: 130,
                            height: 130,
                            margin: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [
                                scheme.primaryContainer,
                                scheme.primary,
                              ]),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.45),
                                  blurRadius: 60,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.podcasts,
                              size: 52,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  // Live transcript of what Mobina is hearing.
                  ValueListenableBuilder<String>(
                    valueListenable: _assistant.transcript,
                    builder: (context, text, _) {
                      if (text.trim().isEmpty) {
                        return const Text(
                          Strings.voiceListeningHint,
                          style: TextStyle(color: Colors.white38),
                        );
                      }
                      return Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width - 80),
                        child: Text(
                          '«$text»',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 17, height: 1.6),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // Mobina's reply (streams in while thinking, then spoken).
                  ValueListenableBuilder<String>(
                    valueListenable: _assistant.reply,
                    builder: (context, reply, _) {
                      if (reply.trim().isEmpty) {
                        return const SizedBox(height: 20);
                      }
                      return Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width - 60),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          reply,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.6),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    Strings.voiceChatHint,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _phaseLabel(MobinaPhase phase) => switch (phase) {
        MobinaPhase.listening => Strings.voiceListening,
        MobinaPhase.capturing => Strings.voiceCapturing,
        MobinaPhase.thinking => Strings.voiceThinking,
        MobinaPhase.speaking => Strings.voiceSpeaking,
        MobinaPhase.idle => Strings.voiceIdle,
      };
}
