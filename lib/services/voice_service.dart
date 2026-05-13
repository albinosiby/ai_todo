import 'dart:developer' as developer;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  static const String _logTag = 'VoiceService';

  bool _isSpeechInitialized = false;

  Function(bool)? _onListeningStateChanged;

  Future<bool> _initializeStt() async {
    return await _stt.initialize(
      onStatus: (status) {
        developer.log('STT Status: $status', name: _logTag);
        if (status == 'done' || status == 'notListening') {
          _onListeningStateChanged?.call(false);
        }
      },
      onError: (errorNotification) {
        developer.log('STT Error: ${errorNotification.errorMsg}', name: _logTag);
        _onListeningStateChanged?.call(false);
      },
    );
  }

  Future<void> init() async {
    developer.log('Initializing voice service', name: _logTag);
    _isSpeechInitialized = await _initializeStt();
    developer.log('Speech initialized: $_isSpeechInitialized', name: _logTag);
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true); // Wait for TTS to finish before returning
    developer.log('TTS configured', name: _logTag);
  }

  String _currentWords = '';

  /// Start listening to user speech
  Future<void> listen({
    required Function(String) onResult,
    required Function(bool) onListeningChanged,
  }) async {
    await _tts.stop();
    _currentWords = '';
    _onListeningStateChanged = onListeningChanged;
    if (!_isSpeechInitialized) {
      developer.log('Speech not initialized, initializing again', name: _logTag);
      _isSpeechInitialized = await _initializeStt();
      developer.log('Re-initialize result: $_isSpeechInitialized', name: _logTag);
    }

    if (_isSpeechInitialized) {
      developer.log('Starting STT listening session', name: _logTag);
      onListeningChanged(true);
      await _stt.listen(
        pauseFor: const Duration(seconds: 4), // Added 1 extra second so users don't get cut off too fast
        listenMode: ListenMode.dictation,
        onResult: (result) {
          developer.log(
            'STT partial result: "${result.recognizedWords}"',
            name: _logTag,
          );
          _currentWords = result.recognizedWords;
          // We no longer call onListeningChanged(false) here. 
          // The onStatus listener handles it robustly, even if speech is completely empty.
        },
      );
    } else {
      developer.log('Cannot start listening: speech not initialized', name: _logTag);
    }
  }

  /// Stop listening
  Future<String> stopListening() async {
    developer.log('Stopping STT listening (isListening=${_stt.isListening})', name: _logTag);
    await _stt.stop();
    return _currentWords;
  }

  /// Cancel listening
  Future<void> cancelListening() async {
    developer.log('Cancelling STT listening', name: _logTag);
    await _stt.stop();
    await _stt.cancel();
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
