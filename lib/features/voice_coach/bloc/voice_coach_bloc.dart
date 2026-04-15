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

  const VoiceCoachState({
    this.status = VoiceCoachStatus.initial,
    this.lastSpeech = '',
    this.coachResponse = 'Hello! I am your task coach. What is on your mind today?',
    this.currentTask,
    this.awaitingTaskConfirmation = false,
    this.pendingTaskContext = '',
  });

  VoiceCoachState copyWith({
    VoiceCoachStatus? status,
    String? lastSpeech,
    String? coachResponse,
    Task? currentTask,
    bool? awaitingTaskConfirmation,
    String? pendingTaskContext,
  }) {
    return VoiceCoachState(
      status: status ?? this.status,
      lastSpeech: lastSpeech ?? this.lastSpeech,
      coachResponse: coachResponse ?? this.coachResponse,
      currentTask: currentTask ?? this.currentTask,
      awaitingTaskConfirmation:
          awaitingTaskConfirmation ?? this.awaitingTaskConfirmation,
      pendingTaskContext: pendingTaskContext ?? this.pendingTaskContext,
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
    emit(state.copyWith(status: VoiceCoachStatus.listening));
    await _voiceService.listen(
      onResult: (speech) {
        developer.log(
          'Speech result received (len=${speech.length}): "$speech"',
          name: _logTag,
        );
        add(ProcessUserSpeechEvent(speech));
      },
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
    await _voiceService.stopListening();
  }

  Future<void> _onInterruptInteraction(
    InterruptInteractionEvent event,
    Emitter<VoiceCoachState> emit,
  ) async {
    developer.log('InterruptInteractionEvent received', name: _logTag);
    _activeRequestId++;
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    emit(state.copyWith(
      status: VoiceCoachStatus.initial,
      awaitingTaskConfirmation: false,
      pendingTaskContext: '',
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
    emit(state.copyWith(status: VoiceCoachStatus.processing, lastSpeech: speech));
    try {
      if (state.awaitingTaskConfirmation) {
        if (_isTaskCreationConfirmation(speech)) {
          final mergedPrompt = state.pendingTaskContext.isEmpty
              ? speech
              : '${state.pendingTaskContext}\n$speech';
          await _createAndPersistTask(
            requestId: requestId,
            prompt: mergedPrompt,
            emit: emit,
          );
          return;
        }

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
        ));
        await _voiceService.speak(
          '$followUpResponse. When ready, say create this task.',
        );
        emit(state.copyWith(status: VoiceCoachStatus.initial));
        return;
      }

      final response = await _buildClarifyingResponse(
        requestId: requestId,
        speech: speech,
      );
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

      emit(state.copyWith(status: VoiceCoachStatus.speaking, coachResponse: response));
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
          'Task intent detected; waiting for confirmation requestId=$requestId',
          name: _logTag,
        );
        emit(state.copyWith(
          status: VoiceCoachStatus.initial,
          awaitingTaskConfirmation: true,
          pendingTaskContext: speech,
          coachResponse: '$response\n\nWhen ready, say: "create this task".',
        ));
      } else {
        developer.log(
          'No task trigger for requestId=$requestId, returning to initial',
          name: _logTag,
        );
        emit(state.copyWith(
          status: VoiceCoachStatus.initial,
          awaitingTaskConfirmation: false,
          pendingTaskContext: '',
        ));
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

  DateTime? _extractReminderTime(String speech) {
    final normalized = speech.toLowerCase();
    final asksReminder = normalized.contains('remind') ||
        normalized.contains('notify') ||
        normalized.contains('notification') ||
        normalized.contains('alert me') ||
        normalized.contains('ping me');
    if (!asksReminder) {
      return null;
    }

    final now = DateTime.now();
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

  Future<void> _createAndPersistTask({
    required int requestId,
    required String prompt,
    required Emitter<VoiceCoachState> emit,
  }) async {
    final reminderTime = _extractReminderTime(prompt);
    final task = (await _geminiService.decomposeTask(prompt)).copyWith(
      sourcePrompt: prompt,
      reminderAt: reminderTime,
      clearReminderAt: reminderTime == null,
    );
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
    ));

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
}
