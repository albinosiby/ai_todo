import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import '../models/task_model.dart';
import '../core/constants/constants.dart';

class GeminiService {
  final String _apiKey = AppConstants.geminiApiKey;
  static const String _logTag = 'GeminiService';
  static const List<String> _candidateModels = <String>[
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-3.1-pro',
    'gemini-3-flash',
  ];
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  GeminiService();

  /// Chat conversation taking full history into account
  Future<String> getChatResponse(List<Map<String, String>> history) async {
    final stopwatch = Stopwatch()..start();
    developer.log(
      'getChatResponse started (history len=${history.length})',
      name: _logTag,
    );
    
    final systemInstruction = '''
You are a friendly, helpful, and strategic AI assistant.
You can engage in normal, everyday conversation. 
However, you are also an expert productivity coach. If the user mentions wanting to learn something, start a project, or create a plan, help them clarify their goal by asking 1-2 thoughtful questions to understand their deadline or scope.
Tone: Conversational, warm, and professional.
Keep responses concise and natural for voice interaction.
''';

    try {
      final responseText = await _generateTextWithFallback(
        history: history,
        systemInstruction: systemInstruction,
        timeout: const Duration(seconds: 20),
        operationName: 'getChatResponse',
        expectJsonResponse: false,
      );
      stopwatch.stop();
      return responseText.isNotEmpty
          ? responseText
          : 'I am here to help. What is on your mind?';
    } catch (e, s) {
      stopwatch.stop();
      developer.log('getChatResponse failed', name: _logTag, error: e, stackTrace: s);
      return 'I am having trouble processing that. Can we try again?';
    }
  }

  /// Kept for backwards compatibility if needed, but getChatResponse is preferred
  Future<String> getClarifyingQuestions(String userTranscript) async {
    return getChatResponse([{'role': 'user', 'text': userTranscript}]);
  }

  /// Decomposes a task into actionable sub-tasks
  Future<Task> decomposeTask(String taskTitle) async {
    final prompt =
        '''
    Context: You are a Strategic Productivity Engine.
    Task: Decompose the goal "$taskTitle" into a high-level strategic plan.

    Rules for SMART Sub-tasks:
    - NEVER provide generic steps like "Read notes" or "Start working."
    - ALWAYS provide actionable, high-impact steps. (e.g., "Set up a distraction-free environment and gather 3 core resources" or "Conduct a 20-minute active recall session on the first 2 chapters").
    - For GOALS: Focus on the 80/20 rule (identify the 20% of work that gives 80% of results).
    - For RECURRING: Include a "trigger" step (e.g., "Place the item next to your car keys as a visual cue").

    Format: Return ONLY a JSON object:
    {
      "title": "Strategy: $taskTitle",
      "description": "A focused roadmap to achieve this goal.",
      "subTasks": [
        {"title": "Actionable Strategic Step 1"},
        {"title": "Actionable Strategic Step 2"}
      ]
    }
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
        expectJsonResponse: true,
      );
      final data = jsonDecode(_extractJsonObject(responseText));
      final task = Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: data['title'] ?? taskTitle,
        description: data['description'] ?? '',
        createdAt: DateTime.now(),
        subTasks: (data['subTasks'] as List? ?? [])
            .map(
              (s) => SubTask(
                id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
                title: s['title'] ?? '',
              ),
            )
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
    String? prompt,
    List<Map<String, String>>? history,
    String? systemInstruction,
    required Duration timeout,
    required String operationName,
    required bool expectJsonResponse,
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
          history: history,
          systemInstruction: systemInstruction,
          timeout: timeout,
          expectJsonResponse: expectJsonResponse,
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
    String? prompt,
    List<Map<String, String>>? history,
    String? systemInstruction,
    required Duration timeout,
    required bool expectJsonResponse,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(
        '$_baseUrl/models/$modelName:generateContent?key=$_apiKey',
      );
      
      final List<Map<String, dynamic>> contents = [];
      
      if (history != null && history.isNotEmpty) {
        contents.addAll(history.map((msg) => {
          'role': msg['role'],
          'parts': [{'text': _sanitizePrompt(msg['text'] ?? '')}],
        }));
      } else if (prompt != null) {
        contents.add({
          'role': 'user',
          'parts': [{'text': _sanitizePrompt(prompt)}],
        });
      }

      final requestPayload = <String, dynamic>{
        'contents': contents,
      };

      if (systemInstruction != null) {
        requestPayload['systemInstruction'] = {
          'parts': [{'text': _sanitizePrompt(systemInstruction)}]
        };
      }

      if (expectJsonResponse) {
        requestPayload['generationConfig'] = {
          'responseMimeType': 'application/json',
        };
      }

      Future<Map<String, dynamic>> send(Map<String, dynamic> payload) async {
        final request = await client.postUrl(uri).timeout(timeout);
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(payload)));
        final httpResponse = await request.close().timeout(timeout);
        final body = await utf8.decodeStream(httpResponse).timeout(timeout);
        final Map<String, dynamic> decoded = jsonDecode(body);
        return {
          'statusCode': httpResponse.statusCode,
          'decoded': decoded,
        };
      }

      var result = await send(requestPayload);
      var statusCode = result['statusCode'] as int;
      var decoded = result['decoded'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        final errorMsg =
            (decoded['error']?['message'] as String?) ??
            'HTTP $statusCode';

        if (expectJsonResponse &&
            errorMsg.toLowerCase().contains('invalid json payload')) {
          final retryPayload = <String, dynamic>{
            'contents': requestPayload['contents'],
          };
          if (requestPayload.containsKey('systemInstruction')) {
             retryPayload['systemInstruction'] = requestPayload['systemInstruction'];
          }
          result = await send(retryPayload);
          statusCode = result['statusCode'] as int;
          decoded = result['decoded'] as Map<String, dynamic>;
          if (statusCode >= 200 && statusCode < 300) {
            final retryText =
                decoded['candidates']?[0]?['content']?['parts']?[0]?['text']
                    as String?;
            if (retryText != null && retryText.trim().isNotEmpty) {
              return retryText;
            }
          }
        }

        throw StateError(errorMsg);
      }

      final text =
          decoded['candidates']?[0]?['content']?['parts']?[0]?['text']
              as String?;
      if (text == null || text.trim().isEmpty) {
        throw StateError('Empty Gemini response text');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  String _sanitizePrompt(String input) {
    return input
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), ' ')
        .trim();
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
