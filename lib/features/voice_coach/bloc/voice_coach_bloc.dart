import 'dart:developer' as developer;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/task_model.dart';
import '../../../services/gemini_service.dart';
import '../../../services/voice_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/task_service.dart';

// Events
abstract class VoiceCoachEvent extends Equatable {
  const VoiceCoachEvent();
  @override
  List<Object> get props => [];
}

class StartListeningEvent extends VoiceCoachEvent {}
class StopListeningEvent extends VoiceCoachEvent {}
class InterruptInteractionEvent extends VoiceCoachEvent {}
class ProcessUserSpeechEvent extends VoiceCoachEvent {
  final String speech;
  const ProcessUserSpeechEvent(this.speech);
  @override
  List<Object> get props => [speech];
}

// State
enum VoiceCoachStatus { initial, listening, processing, speaking, success, failure }

class VoiceCoachState extends Equatable {
  final VoiceCoachStatus status;
  final String lastSpeech;
  final String coachResponse;
  final Task? currentTask;
  final bool awaitingTaskConfirmation;
  final String pendingTaskContext;
  final bool awaitingPlanApproval;
  final Task? pendingDraftTask;
  final List<Map<String, String>> chatHistory;

  const VoiceCoachState({
    this.status = VoiceCoachStatus.initial,
    this.lastSpeech = '',
    this.coachResponse = 'Hello! I am your task coach. What is on your mind today?',
    this.currentTask,
    this.awaitingTaskConfirmation = false,
    this.pendingTaskContext = '',
    this.awaitingPlanApproval = false,
    this.pendingDraftTask,
    this.chatHistory = const [],
  });

  VoiceCoachState copyWith({
    VoiceCoachStatus? status,
    String? lastSpeech,
    String? coachResponse,
    Task? currentTask,
    bool? awaitingTaskConfirmation,
    String? pendingTaskContext,
    bool? awaitingPlanApproval,
    Task? pendingDraftTask,
    List<Map<String, String>>? chatHistory,
    bool clearPendingDraftTask = false,
  }) {
    return VoiceCoachState(
      status: status ?? this.status,
      lastSpeech: lastSpeech ?? this.lastSpeech,
      coachResponse: coachResponse ?? this.coachResponse,
      currentTask: currentTask ?? this.currentTask,
      awaitingTaskConfirmation:
          awaitingTaskConfirmation ?? this.awaitingTaskConfirmation,
      pendingTaskContext: pendingTaskContext ?? this.pendingTaskContext,
      awaitingPlanApproval: awaitingPlanApproval ?? this.awaitingPlanApproval,
      pendingDraftTask:
          clearPendingDraftTask ? null : pendingDraftTask ?? this.pendingDraftTask,
      chatHistory: chatHistory ?? this.chatHistory,
    );
  }

  @override
  List<Object?> get props => [
        status,
        lastSpeech,
        coachResponse,
        currentTask,
        awaitingTaskConfirmation,
        pendingTaskContext,
        awaitingPlanApproval,
        pendingDraftTask,
        chatHistory,
      ];
}

// BLoC
class VoiceCoachBloc extends Bloc<VoiceCoachEvent, VoiceCoachState> {
  final GeminiService _geminiService;
  final VoiceService _voiceService;
  final NotificationService _notificationService;
  final TaskService _taskService;
  int _activeRequestId = 0;
  static const String _logTag = 'VoiceCoachBloc';

  VoiceCoachBloc({
    required GeminiService geminiService,
    required VoiceService voiceService,
    required NotificationService notificationService,
    required TaskService taskService,
  })  : _geminiService = geminiService,
        _voiceService = voiceService,
        _notificationService = notificationService,
        _taskService = taskService,
        super(const VoiceCoachState()) {
    on<StartListeningEvent>(_onStartListening);
    on<StopListeningEvent>(_onStopListening);
    on<InterruptInteractionEvent>(_onInterruptInteraction);
    on<ProcessUserSpeechEvent>(_onProcessSpeech);
  }

  Future<void> _onStartListening(StartListeningEvent event, Emitter<VoiceCoachState> emit) async {
    developer.log('StartListeningEvent received', name: _logTag);
    _activeRequestId++;
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    emit(state.copyWith(status: VoiceCoachStatus.listening, lastSpeech: ''));
    await _voiceService.listen(
      onResult: (_) {},
      onListeningChanged: (isListening) {
        developer.log('Listening changed: $isListening', name: _logTag);
        if (!isListening && state.status == VoiceCoachStatus.listening) {
          add(StopListeningEvent());
        }
      },
    );
  }

  Future<void> _onStopListening(StopListeningEvent event, Emitter<VoiceCoachState> emit) async {
    developer.log('StopListeningEvent received', name: _logTag);
    final words = await _voiceService.stopListening();
    add(ProcessUserSpeechEvent(words));
  }

  Future<void> _onInterruptInteraction(
    InterruptInteractionEvent event,
    Emitter<VoiceCoachState> emit,
  ) async {
    developer.log('InterruptInteractionEvent received', name: _logTag);
    _activeRequestId++;
    await _voiceService.cancelListening();
    await _voiceService.stopSpeaking();
    emit(state.copyWith(
      status: VoiceCoachStatus.initial,
      awaitingTaskConfirmation: false,
      pendingTaskContext: '',
      awaitingPlanApproval: false,
      clearPendingDraftTask: true,
    ));
  }

  Future<void> _onProcessSpeech(ProcessUserSpeechEvent event, Emitter<VoiceCoachState> emit) async {
    final speech = event.speech.trim();
    developer.log(
      'ProcessUserSpeechEvent received (trimmed len=${speech.length})',
      name: _logTag,
    );
    if (speech.isEmpty) {
      developer.log('Ignoring empty speech', name: _logTag);
      emit(state.copyWith(
        status: VoiceCoachStatus.initial,
        coachResponse: 'I did not hear anything. Please try again.',
      ));
      return;
    }

    final int requestId = ++_activeRequestId;
    developer.log(
      'Starting requestId=$requestId, activeRequestId=$_activeRequestId',
      name: _logTag,
    );
    await _voiceService.stopListening();
    
    final updatedHistory = List<Map<String, String>>.from(state.chatHistory)
      ..add({'role': 'user', 'text': speech});

    emit(state.copyWith(
      status: VoiceCoachStatus.processing, 
      lastSpeech: speech,
      chatHistory: updatedHistory,
    ));
    try {
      if (state.awaitingTaskConfirmation) {
        if (state.awaitingPlanApproval && state.pendingDraftTask != null) {
          if (_isPlanApproval(speech)) {
            await _persistDraftTask(
              requestId: requestId,
              draftTask: state.pendingDraftTask!,
              emit: emit,
            );
            return;
          }

          // User continued conversation instead of approving the preview.
          final mergedContext = state.pendingTaskContext.isEmpty
              ? speech
              : '${state.pendingTaskContext}\n$speech';
          final followUpResponse = await _buildClarifyingResponse(
            requestId: requestId,
            speech: mergedContext,
          );
          if (requestId != _activeRequestId) return;
          emit(state.copyWith(
            status: VoiceCoachStatus.speaking,
            coachResponse:
                '$followUpResponse\n\nWhen ready, say: "create this task".',
            awaitingTaskConfirmation: true,
            pendingTaskContext: mergedContext,
            awaitingPlanApproval: false,
            clearPendingDraftTask: true,
          ));
          await _voiceService.speak(
            '$followUpResponse. When ready, say create this task.',
          );
          add(StartListeningEvent());
          return;
        }

        if (_isTaskCreationConfirmation(speech)) {
          final mergedPrompt = state.pendingTaskContext.isEmpty
              ? speech
              : '${state.pendingTaskContext}\n$speech';
          final draftTask = await _buildDraftTask(
            requestId: requestId,
            prompt: mergedPrompt,
          );
          if (requestId != _activeRequestId) return;
          final planPreview = _summarizePlan(draftTask);
          emit(state.copyWith(
            status: VoiceCoachStatus.speaking,
            coachResponse:
                '$planPreview\n\nIf this looks good, say: "approve plan".',
            awaitingTaskConfirmation: true,
            awaitingPlanApproval: true,
            pendingTaskContext: mergedPrompt,
            pendingDraftTask: draftTask,
          ));
          await _voiceService.speak(
            'I created a draft action plan. If it looks good, say approve plan.',
          );
          add(StartListeningEvent());
          return;
        }

        final mergedContext = state.pendingTaskContext.isEmpty
            ? speech
            : '${state.pendingTaskContext}\n$speech';
            
        final contextHistory = List<Map<String, String>>.from(state.chatHistory)
          ..add({'role': 'user', 'text': 'I need to plan this: $mergedContext'});
          
        final followUpResponse = await _geminiService.getChatResponse(contextHistory);
        
        if (requestId != _activeRequestId) return;
        
        final newHistory = List<Map<String, String>>.from(updatedHistory)
          ..add({'role': 'model', 'text': followUpResponse});
        emit(state.copyWith(
          status: VoiceCoachStatus.speaking,
          coachResponse:
              '$followUpResponse\n\nWhen ready, say: "create this task".',
          awaitingTaskConfirmation: true,
          pendingTaskContext: mergedContext,
          awaitingPlanApproval: false,
          clearPendingDraftTask: true,
          chatHistory: newHistory,
        ));
        await _voiceService.speak(
          '$followUpResponse. When ready, say create this task.',
        );
        add(StartListeningEvent());
        return;
      }

      if (_shouldCreateTask(speech) && _isSimpleTaskIntent(speech)) {
        await _createSimpleReminderTask(
          requestId: requestId,
          speech: speech,
          updatedHistory: updatedHistory,
          emit: emit,
        );
        return;
      }

      final response = await _geminiService.getChatResponse(updatedHistory);
      
      if (requestId != _activeRequestId) {
        developer.log(
          'Ignoring stale clarifying response for requestId=$requestId '
          '(active=$_activeRequestId)',
          name: _logTag,
        );
        return;
      }
      developer.log(
        'Clarifying response received for requestId=$requestId (len=${response.length})',
        name: _logTag,
      );

      final newHistory = List<Map<String, String>>.from(updatedHistory)
        ..add({'role': 'model', 'text': response});

      emit(state.copyWith(
        status: VoiceCoachStatus.speaking, 
        coachResponse: response,
        chatHistory: newHistory,
      ));
      await _voiceService.speak(response);
      if (requestId != _activeRequestId) {
        developer.log(
          'Ignoring stale post-TTS flow for requestId=$requestId '
          '(active=$_activeRequestId)',
          name: _logTag,
        );
        return;
      }

      if (_shouldCreateTask(speech)) {
        developer.log(
          'Complex task intent detected; waiting for details requestId=$requestId',
          name: _logTag,
        );
        emit(state.copyWith(
          status: VoiceCoachStatus.speaking, // Keeping speaking status as StartListening will switch to listening immediately
          awaitingTaskConfirmation: true,
          pendingTaskContext: speech,
          coachResponse:
              '$response\n\nI will draft a plan after your details. Then I will ask for approval.',
          awaitingPlanApproval: false,
          clearPendingDraftTask: true,
        ));
        add(StartListeningEvent());
      } else {
        developer.log(
          'No task trigger for requestId=$requestId, auto-resuming listening',
          name: _logTag,
        );
        add(StartListeningEvent());
      }
    } catch (e, s) {
      if (requestId != _activeRequestId) {
        developer.log(
          'Ignoring stale error for requestId=$requestId (active=$_activeRequestId)',
          name: _logTag,
          error: e,
          stackTrace: s,
        );
        return;
      }
      developer.log(
        'Process speech failed for requestId=$requestId',
        name: _logTag,
        error: e,
        stackTrace: s,
      );
      const failureText =
          'I am having trouble reaching Gemini right now. Please try again.';
      emit(state.copyWith(
        status: VoiceCoachStatus.failure,
        coachResponse: failureText,
        awaitingTaskConfirmation: false,
        pendingTaskContext: '',
        awaitingPlanApproval: false,
        clearPendingDraftTask: true,
      ));
      await _voiceService.speak(failureText);
    }
  }

  bool _shouldCreateTask(String speech) {
    final normalized = speech.toLowerCase();
    final hasTaskWord = normalized.contains('task');
    final hasCreateIntent = normalized.contains('create') ||
        normalized.contains('add') ||
        normalized.contains('new');
    if (hasTaskWord && hasCreateIntent) {
      return true;
    }
    const triggerPhrases = <String>[
      'create task',
      'create a task',
      'new task',
      'add task',
      'learn',
      'study',
      'teach me',
      'i have to learn',
      'i want to learn',
      'remind me to',
      'notify me to',
      'break down',
      'decompose',
      'plan',
      'need to',
      'i should',
      'todo',
      'to do',
    ];
    return triggerPhrases.any(normalized.contains);
  }

  bool _isSimpleTaskIntent(String speech) {
    final normalized = speech.toLowerCase();
    final hasComplexKeywords = normalized.contains('learn') ||
        normalized.contains('study') ||
        normalized.contains('project') ||
        normalized.contains('goal') ||
        normalized.contains('roadmap') ||
        normalized.contains('plan for') ||
        normalized.contains('strategy') ||
        normalized.contains('break down') ||
        normalized.contains('decompose');
    if (hasComplexKeywords) return false;

    final hasReminderCue = normalized.contains('remind me') ||
        normalized.contains('notify me') ||
        normalized.contains('remember to');
    if (hasReminderCue) {
      // "and 2 o'clock" is usually time detail, not a second task.
      return true;
    }

    final hasMultipleActions =
        normalized.contains(',') || normalized.contains(' and ');
    if (hasMultipleActions) return false;

    // Short one-action instructions are treated as simple reminders.
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return words <= 10;
  }

  DateTime? _extractReminderTime(String speech) {
    final normalized = speech.toLowerCase();
    final now = DateTime.now();

    // Parse explicit clock time even without "remind me".
    final timeMatch = RegExp(
      r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|o''clock|oclock)?\b',
    ).firstMatch(normalized);
    if (timeMatch != null) {
      var hour = int.tryParse(timeMatch.group(1) ?? '');
      final minute = int.tryParse(timeMatch.group(2) ?? '') ?? 0;
      final meridiem = timeMatch.group(3);
      if (hour != null) {
        if (meridiem == 'pm' && hour < 12) hour += 12;
        if (meridiem == 'am' && hour == 12) hour = 0;
        if ((meridiem == 'o''clock' || meridiem == 'oclock') && hour <= 12) {
          // Keep as spoken hour in 24h style; if already passed, schedule tomorrow.
        }
        var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
        if (scheduled.isBefore(now)) {
          scheduled = scheduled.add(const Duration(days: 1));
        }
        return scheduled;
      }
    }

    // Parse word-based clock times like "two o'clock", "six pm".
    final wordTimeMatch = RegExp(
      r'\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b(?:\s*o''clock|\s*(am|pm))?',
    ).firstMatch(normalized);
    if (wordTimeMatch != null) {
      final word = wordTimeMatch.group(1) ?? '';
      final meridiem = wordTimeMatch.group(2);
      final wordToHour = <String, int>{
        'one': 1,
        'two': 2,
        'three': 3,
        'four': 4,
        'five': 5,
        'six': 6,
        'seven': 7,
        'eight': 8,
        'nine': 9,
        'ten': 10,
        'eleven': 11,
        'twelve': 12,
      };
      var hour = wordToHour[word];
      if (hour != null) {
        if (meridiem == 'pm' && hour < 12) hour += 12;
        if (meridiem == 'am' && hour == 12) hour = 0;
        var scheduled = DateTime(now.year, now.month, now.day, hour);
        if (scheduled.isBefore(now)) {
          scheduled = scheduled.add(const Duration(days: 1));
        }
        return scheduled;
      }
    }

    final asksReminder = normalized.contains('remind') ||
        normalized.contains('notify') ||
        normalized.contains('notification') ||
        normalized.contains('alert me') ||
        normalized.contains('ping me');
    if (!asksReminder) {
      return null;
    }
    final minuteMatch =
        RegExp(r'in\s+(\d+)\s*(minute|minutes|min|mins)\b').firstMatch(normalized);
    if (minuteMatch != null) {
      final minutes = int.tryParse(minuteMatch.group(1) ?? '');
      if (minutes != null && minutes > 0) {
        return now.add(Duration(minutes: minutes));
      }
    }

    final hourMatch = RegExp(r'in\s+(\d+)\s*(hour|hours|hr|hrs)\b').firstMatch(normalized);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? '');
      if (hours != null && hours > 0) {
        return now.add(Duration(hours: hours));
      }
    }

    if (normalized.contains('tomorrow')) {
      return DateTime(now.year, now.month, now.day + 1, 9);
    }
    return now.add(const Duration(hours: 1));
  }

  String? _nextStepFor(Task task) {
    for (final subTask in task.subTasks) {
      if (!subTask.isCompleted) {
        return subTask.title;
      }
    }
    return null;
  }

  String _shortErrorReason(Object error) {
    final raw = error.toString().replaceAll('\n', ' ');
    if (raw.length > 120) {
      return '${raw.substring(0, 120)}...';
    }
    return raw;
  }

  bool _isTaskCreationConfirmation(String speech) {
    final normalized = speech.toLowerCase();
    const confirmations = <String>[
      'create this task',
      'create task now',
      'go ahead',
      'yes create',
      'create it',
      'yes proceed',
      'proceed',
      'looks good create',
    ];
    return confirmations.any(normalized.contains);
  }

  bool _isPlanApproval(String speech) {
    final normalized = speech.toLowerCase();
    const approvals = <String>[
      'approve',
      'approved',
      'yes',
      'looks good',
      'okay',
      'ok',
      'confirm',
      'save',
      'perfect',
      'sure',
      'go ahead',
    ];
    return approvals.any(normalized.contains);
  }

  // Kept for backwards compatibility if needed elsewhere
  Future<String> _buildClarifyingResponse({
    required int requestId,
    required String speech,
  }) async {
    try {
      return await _geminiService
          .getClarifyingQuestions(speech)
          .timeout(const Duration(seconds: 20));
    } catch (e, s) {
      developer.log(
        'Clarifying questions failed for requestId=$requestId',
        name: _logTag,
        error: e,
        stackTrace: s,
      );
      final reason = _shortErrorReason(e);
      return 'I could not reach Gemini for smart questions. Reason: $reason.';
    }
  }

  Future<Task> _buildDraftTask({
    required int requestId,
    required String prompt,
  }) async {
    final reminderTime = _extractReminderTime(prompt);
    final task = (await _geminiService.decomposeTask(prompt)).copyWith(
      sourcePrompt: prompt,
      reminderAt: reminderTime,
      clearReminderAt: reminderTime == null,
    );
    if (requestId != _activeRequestId) {
      developer.log(
        'Ignoring stale draft decomposition for requestId=$requestId '
        '(active=$_activeRequestId)',
        name: _logTag,
      );
    }
    return task;
  }

  String _summarizePlan(Task draftTask) {
    final buffer = StringBuffer()
      ..writeln('Draft action plan for: ${draftTask.title}')
      ..writeln(draftTask.description.isEmpty
          ? 'Description: Let us execute this step by step.'
          : 'Description: ${draftTask.description}');
    if (draftTask.subTasks.isNotEmpty) {
      final phaseSize = draftTask.subTasks.length >= 20 ? 6 : 4;
      final phaseCount = (draftTask.subTasks.length / phaseSize).ceil();
      for (int phase = 0; phase < phaseCount; phase++) {
        final start = phase * phaseSize;
        final endExclusive = (start + phaseSize) > draftTask.subTasks.length
            ? draftTask.subTasks.length
            : (start + phaseSize);
        buffer.writeln('Phase ${phase + 1}:');
        for (int i = start; i < endExclusive; i++) {
          buffer.writeln('- ${draftTask.subTasks[i].title}');
        }
      }
    } else {
      buffer.writeln('Steps:\n1. Start with the first concrete action now.');
    }
    return buffer.toString().trim();
  }

  Future<void> _persistDraftTask({
    required int requestId,
    required Task draftTask,
    required Emitter<VoiceCoachState> emit,
  }) async {
    final reminderTime = draftTask.reminderAt;
    final task = draftTask;
    if (requestId != _activeRequestId) {
      developer.log(
        'Ignoring stale decomposition for requestId=$requestId (active=$_activeRequestId)',
        name: _logTag,
      );
      return;
    }
    await _taskService.saveTask(task);
    if (requestId != _activeRequestId) {
      developer.log(
        'Ignoring stale task save completion for requestId=$requestId '
        '(active=$_activeRequestId)',
        name: _logTag,
      );
      return;
    }
    developer.log(
      'Task saved successfully id=${task.id} for requestId=$requestId',
      name: _logTag,
    );
    emit(state.copyWith(
      status: VoiceCoachStatus.success,
      currentTask: task,
      awaitingTaskConfirmation: false,
      pendingTaskContext: '',
      awaitingPlanApproval: false,
      clearPendingDraftTask: true,
    ));

    await _voiceService.speak('Awesome! The task and its sub-tasks have been saved to your list.');
    add(StartListeningEvent());

    if (reminderTime != null) {
      final nextStep = _nextStepFor(task);
      await _notificationService.scheduleTaskReminder(
        id: task.id.hashCode.abs() % 100000,
        title: 'Reminder: ${task.title}',
        body: nextStep == null ? 'Time to continue your task.' : 'Next: $nextStep',
        scheduledTime: reminderTime,
      );
      developer.log(
        'Notification scheduled for task id=${task.id} at $reminderTime '
        'requestId=$requestId',
        name: _logTag,
      );
    } else {
      developer.log(
        'No reminder requested for requestId=$requestId',
        name: _logTag,
      );
    }
  }

  Future<void> _createSimpleReminderTask({
    required int requestId,
    required String speech,
    required List<Map<String, String>> updatedHistory,
    required Emitter<VoiceCoachState> emit,
  }) async {
    final reminderTime = _extractReminderTime(speech) ??
        DateTime.now().add(const Duration(hours: 1));
    final title = _buildSimpleTitle(speech);
    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: 'Quick reminder created from your request.',
      createdAt: DateTime.now(),
      reminderAt: reminderTime,
      sourcePrompt: speech,
      subTasks: const [
        SubTask(id: '1', title: 'Complete this task'),
      ],
    );

    if (requestId != _activeRequestId) return;
    await _taskService.saveTask(task);
    if (requestId != _activeRequestId) return;

    await _notificationService.scheduleTaskReminder(
      id: task.id.hashCode.abs() % 100000,
      title: 'Reminder: ${task.title}',
      body: 'Friendly nudge: this is your simple task reminder.',
      scheduledTime: reminderTime,
    );

    final successResponse = 'Got it. This is a simple task, so I set a reminder for you. If you want, I can make a detailed plan too.';
    
    final newHistory = List<Map<String, String>>.from(updatedHistory)
        ..add({'role': 'model', 'text': successResponse});

    emit(state.copyWith(
      status: VoiceCoachStatus.success,
      currentTask: task,
      coachResponse: successResponse,
      awaitingTaskConfirmation: false,
      pendingTaskContext: '',
      awaitingPlanApproval: false,
      clearPendingDraftTask: true,
      chatHistory: newHistory,
    ));
    await _voiceService.speak(
      'Done. I set a reminder for this simple task.',
    );
    add(StartListeningEvent());
  }

  String _buildSimpleTitle(String speech) {
    var title = speech;
    title = title.replaceAll(
      RegExp(r'\b(remind me to|notify me to|please|can you|will you)\b', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) return 'Simple reminder';
    return '${title[0].toUpperCase()}${title.substring(1)}';
  }
}
