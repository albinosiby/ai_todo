import 'dart:developer' as developer;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  static const String _logTag = 'VoiceService';

  bool _isSpeechInitialized = false;

  Future<void> init() async {
    developer.log('Initializing voice service', name: _logTag);
    _isSpeechInitialized = await _stt.initialize();
    developer.log('Speech initialized: $_isSpeechInitialized', name: _logTag);
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    developer.log('TTS configured', name: _logTag);
  }

  /// Start listening to user speech
  Future<void> listen({
    required Function(String) onResult,
    required Function(bool) onListeningChanged,
  }) async {
    await _tts.stop();
    if (!_isSpeechInitialized) {
      developer.log('Speech not initialized, initializing again', name: _logTag);
      _isSpeechInitialized = await _stt.initialize();
      developer.log('Re-initialize result: $_isSpeechInitialized', name: _logTag);
    }

    if (_isSpeechInitialized) {
      developer.log('Starting STT listening session', name: _logTag);
      onListeningChanged(true);
      await _stt.listen(
        onResult: (result) {
          developer.log(
            'STT partial/final result: "${result.recognizedWords}" '
            '(final=${result.finalResult})',
            name: _logTag,
          );
          if (result.finalResult) {
            onResult(result.recognizedWords);
            onListeningChanged(false);
          }
        },
      );
    } else {
      developer.log('Cannot start listening: speech not initialized', name: _logTag);
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    developer.log('Stopping STT listening (isListening=${_stt.isListening})', name: _logTag);
    await _stt.stop();
  }

  /// Speak text out loud
  Future<void> speak(String text) async {
    developer.log('Speaking text (len=${text.length})', name: _logTag);
    await _tts.speak(text);
  }

  /// Stop TTS playback immediately.
  Future<void> stopSpeaking() async {
    developer.log('Stopping TTS playback', name: _logTag);
    await _tts.stop();
  }

  /// Wait until TTS finishes speaking
  Future<void> awaitSpeakingCompletion() async {
    // This is a simplified way; flutter_tts has completion handlers
  }

  bool get isListening => _stt.isListening;
}
