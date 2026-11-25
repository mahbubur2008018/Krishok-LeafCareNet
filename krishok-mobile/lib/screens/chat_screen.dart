import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../providers/app_state.dart';
import '../services/connectivity_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';

// ════════════════════════════════════════════════════════════════════════════════
// CHAT SCREEN — Gemini AI Chat
// ════════════════════════════════════════════════════════════════════════════════

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GeminiService _gemini = GeminiService();
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();

  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  String? _speakingMessageId;
  bool _isListening = false;
  bool? _speechAvailable;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final online = await ConnectivityService.isOnline();
    if (mounted) setState(() => _isOffline = !online);
  }

  Future<void> _initTts({String language = 'bn'}) async {
    await _tts.setLanguage(language == 'bn' ? 'bn-BD' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingMessageId = null);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speakingMessageId = null);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final lang = context.read<AppState>().language;

    _speechAvailable ??= await _speech.initialize(
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );

    if (_speechAvailable != true) return;
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        }
      },
      localeId: lang == 'bn' ? 'bn_BD' : 'en_US',
    );
  }

  Future<void> _toggleSpeak(String messageId, String text) async {
    if (_speakingMessageId == messageId) {
      await _tts.stop();
      setState(() => _speakingMessageId = null);
      return;
    }
    await _tts.stop();
    setState(() => _speakingMessageId = messageId);
    await _tts.speak(text);
  }

  void _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isTyping) return;

    setState(() {
      _messages.add(_ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _inputController.clear();
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final appState = context.read<AppState>();
      final sd = appState.currentData;
      final lang = appState.language;
      final lastScan = appState.scanHistory.isNotEmpty
          ? appState.scanHistory.first
          : null;

      final contextParts = <String>[];
      final isBn = lang == 'bn';

      // Last detected disease
      if (lastScan != null) {
        contextParts.add(
          '${isBn ? 'সর্বশেষ শনাক্ত রোগ' : 'Last detected disease'}:\n'
          '${isBn ? 'রোগ' : 'Disease'}: ${lastScan.diseaseName} (${lastScan.cropModel}), '
          '${isBn ? 'আত্মবিশ্বাস' : 'Confidence'}: ${(lastScan.confidence * 100).toStringAsFixed(1)}%',
        );
        if (lastScan.aiInsight != null && lastScan.aiInsight!.isNotEmpty) {
          contextParts.add(
            '${isBn ? 'পূর্ববর্তী AI বিশ্লেষণ' : 'Previous AI analysis'}:\n${lastScan.aiInsight}',
          );
        }
      }

      // Live sensor data
      if (sd != null) {
        contextParts.add(
          '${isBn ? 'মাঠের সেন্সর ডেটা' : 'Field sensor data'}:\n'
          '${isBn ? 'তাপমাত্রা' : 'Temp'}: ${sd.sht20.temp.toStringAsFixed(1)}°C, '
          '${isBn ? 'বায়ু আর্দ্রতা' : 'Humidity'}: ${sd.sht20.hum.toStringAsFixed(0)}%, '
          '${isBn ? 'মাটির আর্দ্রতা' : 'Soil moisture'}: ${sd.soilMoisture.moisture.toStringAsFixed(0)}%, '
          'N: ${sd.npk.n} mg/kg, P: ${sd.npk.p} mg/kg, K: ${sd.npk.k} mg/kg',
        );
      }

      // Recent conversation
      final userLabel = isBn ? 'কৃষক' : 'User';
      final recent = _messages.length > 1
          ? _messages
              .sublist((_messages.length - 7).clamp(0, _messages.length - 1),
                  _messages.length - 1)
              .map((m) => '${m.isUser ? userLabel : "AI"}: ${m.text}')
              .join('\n')
          : '';
      if (recent.isNotEmpty) {
        contextParts.add(
          '${isBn ? 'সাম্প্রতিক কথোপকথন' : 'Recent conversation'}:\n$recent',
        );
      }

      final reply = await _gemini.chat(
        userMessage: text,
        context: contextParts.join('\n\n'),
        language: lang,
      );

      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_ai',
          text: reply,
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_err',
          text: '❌ Connection failed: $e',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    _tts.stop();
    setState(() {
      _messages.clear();
      _isTyping = false;
      _speakingMessageId = null;
    });
  }

  void _sendSuggestedPrompt(String prompt) {
    _inputController.text = prompt;
    _sendMessage();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: KrishokColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Offline mode banner
          if (_isOffline)
            _OfflineBanner(
              label: context.read<AppState>().language == 'bn'
                  ? '📴 অফলাইন মোড — স্থানীয় জ্ঞানভান্ডার থেকে উত্তর দেওয়া হচ্ছে'
                  : '📴 Offline Mode — Answering from local knowledge base',
            ),
          Expanded(
            child: _messages.isEmpty
                ? _WelcomeState(onPromptTap: _sendSuggestedPrompt)
                : _MessageList(
                    messages: _messages,
                    isTyping: _isTyping,
                    speakingMessageId: _speakingMessageId,
                    scrollController: _scrollController,
                    onSpeak: _toggleSpeak,
                  ),
          ),
          _InputBar(
            controller: _inputController,
            focusNode: _focusNode,
            onSend: _sendMessage,
            isTyping: _isTyping,
            isListening: _isListening,
            onVoiceTap: _toggleVoice,
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: KrishokColors.cardWhite,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: KrishokColors.mintGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.messageCircle,
                size: 20, color: KrishokColors.primaryGreen),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.s.chatScreenTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: KrishokColors.textDark,
                ),
              ),
              Text(
                context.s.poweredByAi,
                style: const TextStyle(
                  fontSize: 11,
                  color: KrishokColors.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_messages.isNotEmpty)
          IconButton(
            onPressed: _clearChat,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.trash2,
                  size: 16, color: Colors.redAccent),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CHAT MESSAGE MODEL
// ════════════════════════════════════════════════════════════════════════════════

class _ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  const _ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}

// ════════════════════════════════════════════════════════════════════════════════
// WELCOME STATE
// ════════════════════════════════════════════════════════════════════════════════

class _WelcomeState extends StatelessWidget {
  final ValueChanged<String> onPromptTap;
  const _WelcomeState({required this.onPromptTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),

          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: KrishokColors.primaryGreen.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 36, color: Colors.white),
          ),

          const SizedBox(height: 24),

          Text(
            context.s.welcomeTitle,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KrishokColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.s.welcomeSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: KrishokColors.textMedium,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 36),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.s.suggestedQuestions,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: KrishokColors.textLight,
              ),
            ),
          ),
          const SizedBox(height: 14),

          ...(context.s.chatSuggestions.map((prompt) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SuggestionChip(
                  text: prompt,
                  onTap: () => onPromptTap(prompt),
                ),
              ))),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: KrishokColors.cardWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: KrishokColors.primaryGreen.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.messageCircle,
                size: 16, color: KrishokColors.primaryGreen),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: KrishokColors.textDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: KrishokColors.textLight),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// MESSAGE LIST
// ════════════════════════════════════════════════════════════════════════════════

class _MessageList extends StatelessWidget {
  final List<_ChatMessage> messages;
  final bool isTyping;
  final String? speakingMessageId;
  final ScrollController scrollController;
  final void Function(String id, String text) onSpeak;

  const _MessageList({
    required this.messages,
    required this.isTyping,
    required this.speakingMessageId,
    required this.scrollController,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length + (isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && isTyping) {
          return const _TypingIndicator();
        }
        final msg = messages[index];
        return _MessageBubble(
          message: msg,
          isSpeaking: speakingMessageId == msg.id,
          onSpeak: () => onSpeak(msg.id, msg.text),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isSpeaking;
  final VoidCallback onSpeak;

  const _MessageBubble({
    required this.message,
    required this.isSpeaking,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final timeStr =
        '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    final bubbleColor = isUser
        ? KrishokColors.primaryGreen
        : message.isError
            ? Colors.red.withValues(alpha: 0.06)
            : KrishokColors.cardWhite;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: KrishokColors.mintGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: KrishokColors.primaryGreen),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                border: message.isError
                    ? Border.all(color: Colors.red.withValues(alpha: 0.2))
                    : null,
                boxShadow: isUser
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: isUser
                          ? Colors.white
                          : message.isError
                              ? Colors.redAccent
                              : KrishokColors.textDark,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.7)
                              : KrishokColors.textLight,
                        ),
                      ),
                      // Speaker button for AI messages only
                      if (!isUser && !message.isError) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onSpeak,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isSpeaking
                                  ? KrishokColors.primaryGreen.withValues(alpha: 0.12)
                                  : KrishokColors.surfaceGray,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              isSpeaking
                                  ? Icons.stop_rounded
                                  : Icons.volume_up_rounded,
                              size: 13,
                              color: isSpeaking
                                  ? KrishokColors.primaryGreen
                                  : KrishokColors.textLight,
                            ),
                          ),
                        ),
                      ],
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
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: KrishokColors.mintGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 14, color: KrishokColors.primaryGreen),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: KrishokColors.cardWhite,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.2;
                    final t = (_controller.value - delay).clamp(0.0, 1.0);
                    final bounce = (t < 0.5 ? t * 2 : (1 - t) * 2);
                    return Container(
                      margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: KrishokColors.primaryGreen
                            .withValues(alpha: 0.3 + bounce * 0.7),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// INPUT BAR
// ════════════════════════════════════════════════════════════════════════════════

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onVoiceTap;
  final bool isTyping;
  final bool isListening;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onVoiceTap,
    required this.isTyping,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isListening
                    ? Colors.red.withValues(alpha: 0.05)
                    : KrishokColors.surfaceGray,
                borderRadius: BorderRadius.circular(24),
                border: isListening
                    ? Border.all(color: Colors.red.withValues(alpha: 0.25))
                    : null,
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  fontSize: 14,
                  color: KrishokColors.textDark,
                ),
                decoration: InputDecoration(
                  hintText: isListening
                      ? (context.s.isBn ? 'শুনছি...' : 'Listening...')
                      : context.s.typeMessage,
                  hintStyle: TextStyle(
                    color: isListening
                        ? Colors.red.withValues(alpha: 0.6)
                        : KrishokColors.textLight,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => onSend(),
                maxLines: null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mic button
          GestureDetector(
            onTap: onVoiceTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isListening
                    ? Colors.red.withValues(alpha: 0.1)
                    : KrishokColors.surfaceGray,
                borderRadius: BorderRadius.circular(14),
                border: isListening
                    ? Border.all(color: Colors.red.withValues(alpha: 0.3))
                    : null,
              ),
              child: Icon(
                isListening ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 20,
                color:
                    isListening ? Colors.red : KrishokColors.textMedium,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          GestureDetector(
            onTap: isTyping ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isTyping
                    ? KrishokColors.primaryGreen.withValues(alpha: 0.5)
                    : KrishokColors.primaryGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                LucideIcons.send,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// OFFLINE BANNER
// ════════════════════════════════════════════════════════════════════════════════

class _OfflineBanner extends StatelessWidget {
  final String label;
  const _OfflineBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFFFF3CD),
      child: Row(
        children: [
          const Icon(LucideIcons.wifiOff, size: 14, color: Color(0xFF856404)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF856404),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
