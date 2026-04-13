import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/services/gemma_chat_service.dart';
import '../../data/repositories/todo_repository.dart';

class AIChatModal extends StatefulWidget {
  const AIChatModal({Key? key}) : super(key: key);

  @override
  State<AIChatModal> createState() => _AIChatModalState();
}

class _AIChatModalState extends State<AIChatModal> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool isListening = false;
  bool _isLoadingModel = true;
  int _downloadPercent = 0;
  bool _isGenerating = false;
  bool _speechAvailable = false;
  bool _isStartingListening = false;

  InferenceModel? _model;
  dynamic _chat;

  final List<_ChatMessage> _messages = [];
  final TodoRepository _todoRepository = TodoRepository();

  final Stopwatch _listenStopwatch = Stopwatch();
  Timer? _listenTicker;
  final ValueNotifier<int> _listenSeconds = ValueNotifier<int>(0);
  DateTime? _lastVoiceStatusMessageAt;
  final Set<String> _handledToolCalls = <String>{};

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  double _recordLevel = 0;
  StreamSubscription<Amplitude>? _ampSub;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() {
        _isLoadingModel = true;
        _downloadPercent = 0;
      });

      await GemmaChatService.instance.ensureModelInstalled(
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _downloadPercent = p);
        },
      );

      final model = await GemmaChatService.instance.createModel();
      final chat = await model.createChat(
        systemInstruction:
            'You are Gemma, a friendly todo assistant. '
            'ONLY call create_todo when the user EXPLICITLY asks to add/create a task or todo. '
            'For greetings, questions, or general chat — reply with plain text only. '
            'NEVER call any tool more than once per user message. '
            'After calling a tool, always wait for the next user message before doing anything. '
            'If you need to show something important, call show_alert(title, message).',
        tools: GemmaChatService.instance.defaultTools(),
        supportsFunctionCalls: true,
        modelType: ModelType.functionGemma,
        toolChoice: ToolChoice.auto,
      );

      if (!mounted) {
        await model.close();
        return;
      }

      setState(() {
        _model = model;
        _chat = chat;
        _isLoadingModel = false;
      });

      final available = await _speech.initialize(
        onError: (e) {
          if (!mounted) return;
          _stopListenUi();
          setState(() => isListening = false);
          final now = DateTime.now();
          final last = _lastVoiceStatusMessageAt;
          if (last == null || now.difference(last) > const Duration(seconds: 2)) {
            _lastVoiceStatusMessageAt = now;
            // Ignore "no match" (silence) to avoid spam.
            if (e.errorMsg == 'error_no_match') return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Voice: ${e.errorMsg}'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'listening') {
            if (!isListening) setState(() => isListening = true);
            _startListenUi();
          }
          if (status == 'notListening') {
            _stopListenUi();
            setState(() => isListening = false);
          }
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = available);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingModel = false;
        _messages.add(_ChatMessage.assistant('Failed to start Gemma: $e'));
      });
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      setState(() {
        _messages.add(_ChatMessage.assistant('Voice input is not available on this device.'));
      });
      return;
    }
    if (_isGenerating) return;
    if (_isStartingListening) return;

    if (isListening) {
      await _speech.stop();
      if (!mounted) return;
      _stopListenUi();
      setState(() => isListening = false);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isStartingListening = true);

    final hasPermission = await _speech.hasPermission;
    if (!mounted) return;
    if (!hasPermission) {
      setState(() {
        _isStartingListening = false;
        isListening = false;
        _messages.add(
          _ChatMessage.assistant('Microphone permission denied. Enable it in system settings and try again.'),
        );
      });
      return;
    }

    // Start listening without making UI feel "stuck".
    setState(() => isListening = true);
    try {
      final startedDynamic = await _speech
          .listen(
            listenFor: const Duration(seconds: 45),
            pauseFor: const Duration(seconds: 3),
            listenOptions: stt.SpeechListenOptions(
              listenMode: stt.ListenMode.dictation,
              partialResults: true,
            ),
            onResult: (result) {
              if (!mounted) return;
              _controller.text = result.recognizedWords;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            },
          )
          .timeout(const Duration(seconds: 10), onTimeout: () => false);

      if (!mounted) return;
      final started = startedDynamic == true;
      setState(() => isListening = started);
      if (started) {
        _startListenUi();
      } else {
        _stopListenUi();
        final now = DateTime.now();
        final last = _lastVoiceStatusMessageAt;
        if (last == null || now.difference(last) > const Duration(seconds: 2)) {
          _lastVoiceStatusMessageAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start voice input. Try again.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _stopListenUi();
      setState(() {
        isListening = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voice failed to start: $e'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isStartingListening = false);
      }
    }
  }

  void _startListenUi() {
    _listenStopwatch
      ..reset()
      ..start();
    _listenTicker?.cancel();
    _listenTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _listenSeconds.value = _listenStopwatch.elapsed.inSeconds;
    });
  }

  void _stopListenUi() {
    _listenStopwatch.stop();
    _listenTicker?.cancel();
    _listenTicker = null;
    _listenSeconds.value = 0;
  }

  void _startRecordUi() {
    _startListenUi();
  }

  void _stopRecordUi() {
    _stopListenUi();
  }

  Future<void> _toggleRecording() async {
    if (_isGenerating) return;
    if (_isLoadingModel) return;

    if (_isRecording) {
      final path = await _recorder.stop();
      await _ampSub?.cancel();
      _ampSub = null;
      if (!mounted) return;
      _stopRecordUi();
      setState(() {
        _isRecording = false;
        _recordLevel = 0;
      });
      if (path != null) {
        setState(() {
          _messages.add(_ChatMessage.assistant('Audio recorded: $path'));
        });
        _scrollToBottom();
      }
      return;
    }

    final hasPerm = await _recorder.hasPermission();
    if (!mounted) return;
    if (!hasPerm) {
      setState(() {
        _messages.add(_ChatMessage.assistant('Microphone permission denied. Enable it in system settings.'));
      });
      return;
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: filePath,
    );

    await _ampSub?.cancel();
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((amp) {
      final db = amp.current; // typically -160..0
      final norm = ((db + 60) / 60).clamp(0.0, 1.0); // map roughly -60..0 => 0..1
      if (!mounted) return;
      setState(() => _recordLevel = norm);
    });

    if (!mounted) return;
    _startRecordUi();
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _chat == null) return;
    if (_isGenerating) return;

    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage.user(text));
      _messages.add(_ChatMessage.assistant('')); // placeholder for streaming
      _isGenerating = true;
    });
    _scrollToBottom();

    final chat = _chat!;
    final int assistantIndex = _messages.length - 1;

    try {
      await _safeAddQueryChunk(chat, Message.text(text: text, isUser: true));
      final gotOutput = await _runModelTurn(chat: chat, assistantIndex: assistantIndex);
      if (mounted && !gotOutput && _messages[assistantIndex].text.trim().isEmpty) {
        setState(() {
          _messages[assistantIndex] = _messages[assistantIndex].copyWith(
            text: 'No response from Gemma. Try again.',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages[assistantIndex] =
            _messages[assistantIndex].copyWith(text: 'Error talking to Gemma: $e');
      });
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
        _scrollToBottom();
      }
    }
  }

  Future<bool> _runModelTurn({
    required dynamic chat,
    required int assistantIndex,
  }) async {
    int toolCallCount = 0;
    const maxToolCalls = 1;
    bool anyOutput = false;

    while (true) {
      bool sawToolCall = false;
      var functionTextBuffer = '';

      var timedOut = false;
      final timeout = Timer(const Duration(seconds: 25), () {
        timedOut = true;
        // Best-effort cancel; avoid starting another inference afterward.
        // ignore: discarded_futures
        chat.stopGeneration();
      });

      try {
        await for (final response in chat.generateChatResponseAsync()) {
          if (!mounted) return anyOutput;
          if (timedOut) return anyOutput;

        if (response is TextResponse) {
          // Fallback: sometimes FunctionGemma tool calls leak through as plain text tokens.
          // Buffer and parse them ourselves so the UI doesn't look "stuck".
          final token = response.token;
          final isToolStart = token.contains('<start_function_call>');
          if (isToolStart || functionTextBuffer.isNotEmpty) {
            functionTextBuffer += token;

            if (FunctionCallParser.isFunctionCallComplete(
              functionTextBuffer,
              modelType: ModelType.functionGemma,
            )) {
              final calls = FunctionCallParser.parseAll(
                functionTextBuffer,
                modelType: ModelType.functionGemma,
              );
              if (calls.isNotEmpty) {
                sawToolCall = true;
                await chat.stopGeneration();
                toolCallCount += calls.length;
                if (toolCallCount > maxToolCalls) return anyOutput;
                for (final call in calls) {
                  if (_shouldHandleToolCall(call)) {
                    await _handleFunctionCall(chat, call);
                    anyOutput = true;
                  }
                }
                // Tool executed; don't re-enter generation to avoid tool-call loops.
                return anyOutput;
              } else {
                // Not a valid tool call; fall through and render as text.
                functionTextBuffer = '';
              }
            }

            // Don't render tool-call tokens as assistant text.
            continue;
          }

          setState(() {
            _messages[assistantIndex] =
                _messages[assistantIndex].copyWith(text: _messages[assistantIndex].text + response.token);
          });
          anyOutput = true;
          _scrollToBottom();
        } else if (response is FunctionCallResponse) {
          sawToolCall = true;
          await chat.stopGeneration();
          toolCallCount += 1;
          if (toolCallCount > maxToolCalls) return anyOutput;
          if (_shouldHandleToolCall(response)) {
            await _handleFunctionCall(chat, response);
            anyOutput = true;
          }
          return anyOutput;
        } else if (response is ParallelFunctionCallResponse) {
          sawToolCall = true;
          await chat.stopGeneration();
          toolCallCount += response.calls.length;
          if (toolCallCount > maxToolCalls) return anyOutput;
          for (final call in response.calls) {
            if (_shouldHandleToolCall(call)) {
              await _handleFunctionCall(chat, call);
              anyOutput = true;
            }
          }
          return anyOutput;
        }
        }
      } finally {
        timeout.cancel();
      }

      if (!sawToolCall) {
        return anyOutput; // normal text completion
      }
    }
  }

  bool _shouldHandleToolCall(FunctionCallResponse call) {
    final sig = '${call.name}|${call.args}';
    return _handledToolCalls.add(sig);
  }

  Future<void> _handleFunctionCall(dynamic chat, FunctionCallResponse functionCall) async {
    Map<String, dynamic> toolResponse;

    switch (functionCall.name) {
      case 'create_todo':
        final title = (functionCall.args['title'] as String?)?.trim();
        final priority = (functionCall.args['priority'] as String?)?.trim();
        final dueAtRaw = (functionCall.args['dueAt'] as String?)?.trim();

        if (title == null || title.isEmpty) {
          setState(() {
            _messages.add(_ChatMessage.assistant('What should the todo title be?'));
          });
          return;
        }

        DateTime? dueAt;
        if (dueAtRaw != null && dueAtRaw.isNotEmpty) {
          dueAt = DateTime.tryParse(dueAtRaw);
        }

        try {
          final id = await _todoRepository.createTodo(
            title: title,
            priority: priority?.isEmpty == true ? null : priority,
            dueAt: dueAt,
          );

          // Always alert the user immediately.
          if (!mounted) {
            toolResponse = {'error': 'UI not mounted'};
            break;
          }
          // ignore: unawaited_futures
          showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Todo created'),
              content: Text('“$title” saved.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );

          toolResponse = {
            'status': 'success',
            'id': id,
            'title': title,
            'priority': priority,
            'dueAt': dueAtRaw,
          };
        } catch (e) {
          toolResponse = {'error': e.toString()};
        }
        break;
      case 'show_alert':
        final title = (functionCall.args['title'] as String?)?.trim();
        final message = (functionCall.args['message'] as String?)?.trim();
        if (title == null || title.isEmpty || message == null || message.isEmpty) {
          toolResponse = {'error': 'Missing title or message'};
          break;
        }

        // Fire-and-forget UI side effect; return success to the model either way.
        // ignore: unawaited_futures
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        toolResponse = {'status': 'success', 'message': 'Alert shown'};
        break;
      default:
        toolResponse = {'error': 'Unknown function: ${functionCall.name}'};
    }

    final toolMessage = Message.toolResponse(
      toolName: functionCall.name,
      response: toolResponse,
    );
    await _safeAddQueryChunk(chat, toolMessage);
  }

  Future<void> _safeAddQueryChunk(dynamic chat, Message message) async {
    // Some backends throw if we add a message while the previous generation is still finishing.
    // Retry briefly instead of crashing the UI.
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await chat.addQueryChunk(message);
        return;
      } on PlatformException catch (e) {
        final msg = (e.message ?? '').toLowerCase();
        final isBusy = msg.contains('previous invocation still processing') || msg.contains('wait for done');
        if (!isBusy || attempt == 5) rethrow;
        try {
          await chat.stopGeneration();
        } catch (_) {
          // ignore
        }
        await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    // ignore: unawaited_futures
    _speech.stop();
    _stopListenUi();
    _listenSeconds.dispose();
    // ignore: unawaited_futures
    _recorder.dispose();
    // ignore: unawaited_futures
    _ampSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _model?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gemma Chat',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _isGenerating ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingModel)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _downloadPercent > 0 ? 'Downloading model… $_downloadPercent%' : 'Preparing Gemma…',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'First run can take a while (FunctionGemma is ~284MB).',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final align = msg.role == _Role.user ? Alignment.centerRight : Alignment.centerLeft;
                  final bubbleColor =
                      msg.role == _Role.user ? colors.primary : colors.surfaceContainerHighest;
                  final textColor = msg.role == _Role.user ? Colors.white : colors.onSurface;

                  return Align(
                    alignment: align,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(msg.text, style: TextStyle(color: textColor)),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          if (isListening) ...[
            _ListeningBar(
              secondsListenable: _listenSeconds,
              onStop: (_isLoadingModel || _isGenerating) ? null : _toggleListening,
            ),
            const SizedBox(height: 8),
          ],
          if (_isRecording) ...[
            _RecordingBar(
              secondsListenable: _listenSeconds,
              level: _recordLevel,
              onStop: (_isLoadingModel || _isGenerating) ? null : _toggleRecording,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Message Gemma…',
                    filled: true,
                    fillColor: colors.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: (_isLoadingModel || _isGenerating) ? null : _toggleListening,
                icon: Icon(isListening ? Icons.mic : Icons.mic_none),
                color: isListening ? colors.secondary : null,
                tooltip: isListening ? 'Stop listening' : 'Voice input',
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: (_isLoadingModel || _isGenerating) ? null : _toggleRecording,
                icon: Icon(_isRecording ? Icons.stop_circle : Icons.fiber_manual_record),
                color: _isRecording ? Colors.redAccent : null,
                tooltip: _isRecording ? 'Stop recording' : 'Record audio',
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                onPressed: (_isLoadingModel || _isGenerating) ? null : _send,
                icon: _isGenerating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Role { user, assistant }

class _ChatMessage {
  final _Role role;
  final String text;

  const _ChatMessage(this.role, this.text);

  factory _ChatMessage.user(String text) => _ChatMessage(_Role.user, text);
  factory _ChatMessage.assistant(String text) => _ChatMessage(_Role.assistant, text);

  _ChatMessage copyWith({String? text}) => _ChatMessage(role, text ?? this.text);
}

class _ListeningBar extends StatefulWidget {
  final ValueListenable<int> secondsListenable;
  final VoidCallback? onStop;

  const _ListeningBar({
    required this.secondsListenable,
    required this.onStop,
  });

  @override
  State<_ListeningBar> createState() => _ListeningBarState();
}

class _ListeningBarState extends State<_ListeningBar> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: colors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Listening', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: widget.secondsListenable,
                      builder: (context, s, _) => Text(
                        '${s}s',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _ac,
                  builder: (context, _) {
                    final t = _ac.value;
                    double bar(int i) {
                      final phase = (t * 6.28318) + (i * 0.7);
                      return 6 + (8 * (0.5 + 0.5 * (sin(phase))));
                    }

                    return Row(
                      children: List.generate(10, (i) {
                        final h = bar(i);
                        return Container(
                          width: 4,
                          height: h,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: colors.secondary.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: widget.onStop,
            icon: const Icon(Icons.stop_circle_outlined),
            color: colors.onSurfaceVariant,
            tooltip: 'Stop',
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  final ValueListenable<int> secondsListenable;
  final double level;
  final VoidCallback? onStop;

  const _RecordingBar({
    required this.secondsListenable,
    required this.level,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bars = 12;
    final active = max(1, (level * bars).round());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Recording', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: secondsListenable,
                      builder: (context, s, _) => Text(
                        '${s}s',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(bars, (i) {
                    final on = i < active;
                    return Container(
                      width: 4,
                      height: 6 + (i % 4) * 4,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: (on ? Colors.redAccent : colors.onSurfaceVariant).withOpacity(on ? 0.9 : 0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined),
            color: colors.onSurfaceVariant,
            tooltip: 'Stop',
          ),
        ],
      ),
    );
  }
}
