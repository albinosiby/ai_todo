import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/task_model.dart';
import 'package:flutter/foundation.dart';

class AIService {
  final String _claudeApiUrl =
      "https://api.anthropic.com/v1/messages"; // Mock endpoint
  final String _geminiApiUrl =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent";
  // TFLite inference would typically use package:tflite_flutter
  // final Interpreter? _tfliteInterpreter;

  AIService();

  /// 1. Goal Breakdown using Claude Haiku
  Future<List<TaskModel>> breakDownGoal(String goalDescription) async {
    debugPrint("Calling Claude API for Goal Breakdown: $goalDescription");
    // Mock Delay simulating Claude Haiku 4.5 response
    await Future.delayed(const Duration(seconds: 2));

    // Mock parsed JSON response mapped to TaskModels
    return [
      TaskModel(
        id: 'mock_ai_task_1',
        title: 'Project Setup & Domain Configuration',
        priority: 'high',
        dueAt: DateTime.now().add(const Duration(hours: 2)),
        order: 1,
      ),
      TaskModel(
        id: 'mock_ai_task_2',
        title: 'Design Database Schema',
        priority: 'high',
        dueAt: DateTime.now().add(const Duration(days: 1)),
        order: 2,
      ),
      TaskModel(
        id: 'mock_ai_task_3',
        title: 'Implement Core Screens',
        priority: 'medium',
        dueAt: DateTime.now().add(const Duration(days: 2)),
        order: 3,
      ),
    ];
  }

  /// 2. General Bulk Text with Gemini 2.5 Flash-Lite
  Future<String> generateMotivation(String goalTitle) async {
    debugPrint("Calling Gemini API for motivation text.");
    await Future.delayed(const Duration(seconds: 1));
    return "You have the power to conquer $goalTitle today! Step into your greatness.";
  }

  /// 3. Voice-to-task parsing with local Gemma 4 / TFLite
  Future<String> parseVoiceInput(String transcribedText) async {
    debugPrint("On-Device Parsing with Gemma 4: $transcribedText");
    // Pseudo TFLite inference
    // final output = _tfliteInterpreter.run(transcribedText);
    await Future.delayed(const Duration(milliseconds: 500));
    return transcribedText; // return raw for now
  }
}
