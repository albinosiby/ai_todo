import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import '../models/task_model.dart';
import '../core/constants/constants.dart';

class GeminiService {
  final String _apiKey = AppConstants.geminiApiKey;
  static const String _logTag = 'GeminiService';
  static const List<String> _candidateModels = <String>[
    'gemini-3-flash',
    'gemini-3.1-flash',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.5-pro',
    'gemini-2.0-flash',
  ];
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1';

  GeminiService();

  /// Asks clarifying questions about a potential task
  Future<String> getClarifyingQuestions(String userTranscript) async {
    final prompt = '''
    Context: You are a productive task coach. A user just said: "$userTranscript".
    Task: If this is a task or goal, ask 1-2 smart, concise clarifying questions to help make it specific and actionable.
    Tone: Encouraging, professional, and coach-like.
    Keep it very brief (under 30 words).
    ''';

    final stopwatch = Stopwatch()..start();
    developer.log(
      'getClarifyingQuestions started (input len=${userTranscript.length})',
      name: _logTag,
    );
    final responseText = await _generateTextWithFallback(
      prompt: prompt,
      timeout: const Duration(seconds: 20),
      operationName: 'getClarifyingQuestions',
    );
    stopwatch.stop();
    developer.log(
      'getClarifyingQuestions success in ${stopwatch.elapsedMilliseconds}ms '
      '(response len=${responseText.length})',
      name: _logTag,
    );
    return responseText.isNotEmpty
        ? responseText
        : 'That sounds interesting. Can you tell me more about what you want to achieve?';
  }

  /// Decomposes a task into actionable sub-tasks
  Future<Task> decomposeTask(String taskTitle) async {
    final prompt = '''
    Context: You are a productive task coach.
    Task: Decompose "$taskTitle" into 3-5 smart, actionable sub-tasks.
    Format: Return ONLY a JSON object with the following structure:
    {
      "title": "Main task title",
      "description": "Short encouraging description",
      "subTasks": [
        {"title": "Subtask 1"},
        {"title": "Subtask 2"}
      ]
    }
    No markdown formatting, no extra text.
    ''';

    final stopwatch = Stopwatch()..start();
    developer.log(
      'decomposeTask started (title len=${taskTitle.length})',
      name: _logTag,
    );
    try {
      final responseText = await _generateTextWithFallback(
        prompt: prompt,
        timeout: const Duration(seconds: 25),
        operationName: 'decomposeTask',
      );
      final data = jsonDecode(_extractJsonObject(responseText));
      final task = Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: data['title'] ?? taskTitle,
        description: data['description'] ?? '',
        createdAt: DateTime.now(),
        subTasks: (data['subTasks'] as List? ?? [])
            .map((s) => SubTask(
                  id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
                  title: s['title'] ?? '',
                ))
            .toList(),
      );
      stopwatch.stop();
      developer.log(
        'decomposeTask success in ${stopwatch.elapsedMilliseconds}ms '
        '(subTasks=${task.subTasks.length})',
        name: _logTag,
      );
      return task;
    } catch (e, s) {
      stopwatch.stop();
      developer.log(
        'decomposeTask failed in ${stopwatch.elapsedMilliseconds}ms; using fallback task',
        name: _logTag,
        error: e,
        stackTrace: s,
      );
      return Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: taskTitle,
        description: "Let's get this done!",
        createdAt: DateTime.now(),
        subTasks: [
          SubTask(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: 'Get started',
          ),
        ],
      );
    }
  }

  Future<String> _generateTextWithFallback({
    required String prompt,
    required Duration timeout,
    required String operationName,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (final modelName in _candidateModels) {
      try {
        developer.log(
          '$operationName trying model "$modelName"',
          name: _logTag,
        );
        final response = await _callGenerateContent(
          modelName: modelName,
          prompt: prompt,
          timeout: timeout,
        );
        developer.log(
          '$operationName succeeded with model "$modelName"',
          name: _logTag,
        );
        return response;
      } catch (e, s) {
        lastError = e;
        lastStackTrace = s;
        developer.log(
          '$operationName failed with model "$modelName"',
          name: _logTag,
          error: e,
          stackTrace: s,
        );
      }
    }

    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace ?? StackTrace.empty);
    }
    throw StateError('No Gemini models attempted for $operationName');
  }

  Future<String> _callGenerateContent({
    required String modelName,
    required String prompt,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(
        '$_baseUrl/models/$modelName:generateContent?key=$_apiKey',
      );
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
      })));

      final httpResponse = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(httpResponse).timeout(timeout);
      final Map<String, dynamic> decoded = jsonDecode(body);

      if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
        final errorMsg = (decoded['error']?['message'] as String?) ??
            'HTTP ${httpResponse.statusCode}';
        throw StateError(errorMsg);
      }

      final text = decoded['candidates']?[0]?['content']?['parts']?[0]?['text']
          as String?;
      if (text == null || text.trim().isEmpty) {
        throw StateError('Empty Gemini response text');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  String _extractJsonObject(String rawText) {
    final String trimmed = rawText.trim();
    final int start = trimmed.indexOf('{');
    final int end = trimmed.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return trimmed.substring(start, end + 1);
    }
    return '{}';
  }
}
