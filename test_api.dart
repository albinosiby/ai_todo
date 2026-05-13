import 'dart:io';
import 'lib/services/gemini_service.dart';

void main() async {
  print('Starting Gemini test...');
  final service = GeminiService();
  try {
    final response = await service.getChatResponse([
      {'role': 'user', 'text': 'Hello, are you there?'}
    ]);
    print('SUCCESS: \$response');
  } catch (e, s) {
    print('ERROR: \$e');
    print(s);
  }
}
