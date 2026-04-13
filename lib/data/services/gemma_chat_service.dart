import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaChatService {
  static const String _functionGemmaUrl =
      'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task';
  static const String _functionGemmaFilename = 'functiongemma-270M-it.task';

  static final GemmaChatService instance = GemmaChatService._();
  GemmaChatService._();

  Future<void> ensureModelInstalled({void Function(int percent)? onProgress}) async {
    final modelManager = FlutterGemmaPlugin.instance.modelManager;

    final isInstalled = await FlutterGemma.isModelInstalled(_functionGemmaFilename);
    if (!isInstalled) {
      final installer = FlutterGemma.installModel(modelType: ModelType.functionGemma).fromNetwork(
        _functionGemmaUrl,
      );
      final withProgress = onProgress == null ? installer : installer.withProgress(onProgress);
      await withProgress.install();
    }

    // Ensure an active/loaded model is selected for inference.
    // This avoids: "Bad state: No active inference model set".
    await modelManager.ensureModelReady(_functionGemmaFilename, _functionGemmaUrl);
  }

  Future<InferenceModel> createModel() {
    // Use legacy creation so we don't depend on global "active model" state.
    return FlutterGemmaPlugin.instance.createModel(
      modelType: ModelType.functionGemma,
      maxTokens: 1024,
      preferredBackend: PreferredBackend.gpu,
    );
  }

  List<Tool> defaultTools() {
    return [
      Tool(
        name: 'create_todo',
        description:
            "Create a todo item in Firebase Firestore. Use this when the user asks to add/create a task/todo/reminder. If dueAt is known, pass ISO-8601 string.",
        parameters: {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Short todo title',
            },
            'priority': {
              'type': 'string',
              'description': "Optional priority like 'low', 'medium', 'high'",
            },
            'dueAt': {
              'type': 'string',
              'description': 'Optional ISO-8601 datetime, e.g. 2026-04-13T18:30:00',
            },
          },
          'required': ['title'],
        },
      ),
      Tool(
        name: 'show_alert',
        description: 'Shows an alert dialog with a custom message and title.',
        parameters: {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'The title of the alert dialog',
            },
            'message': {
              'type': 'string',
              'description': 'The message content of the alert dialog',
            },
          },
          'required': ['title', 'message'],
        },
      ),
    ];
  }
}

