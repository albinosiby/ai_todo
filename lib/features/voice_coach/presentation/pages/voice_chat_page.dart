import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../tasks/presentation/widgets/task_card.dart';
import '../../bloc/voice_coach_bloc.dart';
import '../../../../services/gemini_service.dart';
import '../../../../services/voice_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/task_service.dart';

class VoiceChatPage extends StatelessWidget {
  const VoiceChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => VoiceCoachBloc(
        geminiService: context.read<GeminiService>(),
        voiceService: context.read<VoiceService>(),
        notificationService: context.read<NotificationService>(),
        taskService: context.read<TaskService>(),
      ),
      child: const VoiceChatView(),
    );
  }
}

class VoiceChatView extends StatelessWidget {
  const VoiceChatView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 1.2,
            colors: [
              const Color(0xFF1E293B),
              const Color(0xFF0F172A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _buildChatContent(),
              ),
              _buildVoiceControls(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.indigoAccent),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Task Coach',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Online',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatContent() {
    return BlocBuilder<VoiceCoachBloc, VoiceCoachState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // AI Response
              AnimatedOpacity(
                opacity: state.coachResponse.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    state.coachResponse,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      height: 1.5,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              // Visualizer
              _VoiceVisualizer(status: state.status),
              
              const SizedBox(height: 40),
              
              // User Transcript
              if (state.lastSpeech.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    state.lastSpeech,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.indigoAccent,
                    ),
                  ),
                ),
              
              // Task Breakdown
              if (state.currentTask != null)
                TaskBreakdownCard(task: state.currentTask!),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40.0),
      child: BlocBuilder<VoiceCoachBloc, VoiceCoachState>(
        builder: (context, state) {
          final isListening = state.status == VoiceCoachStatus.listening;
          final isBusy = isListening ||
              state.status == VoiceCoachStatus.processing ||
              state.status == VoiceCoachStatus.speaking;
          
          return GestureDetector(
            onTap: () {
              if (isListening) {
                context.read<VoiceCoachBloc>().add(StopListeningEvent());
              } else {
                context.read<VoiceCoachBloc>().add(StartListeningEvent());
              }
            },
            child: Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isBusy 
                    ? [Colors.redAccent, Colors.pinkAccent]
                    : [Colors.indigoAccent, Colors.blueAccent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isBusy ? Colors.redAccent : Colors.indigoAccent).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                isBusy ? Icons.stop : Icons.mic,
                size: 32,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VoiceVisualizer extends StatefulWidget {
  final VoiceCoachStatus status;
  const _VoiceVisualizer({required this.status});

  @override
  State<_VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<_VoiceVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (widget.status == VoiceCoachStatus.listening || widget.status == VoiceCoachStatus.processing)
              for (int i = 0; i < 3; i++)
                Transform.scale(
                  scale: 1.0 + (_controller.value + i / 3.0) % 1.0 * 2.0,
                  child: Opacity(
                    opacity: (1.0 - (_controller.value + i / 3.0) % 1.0),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.indigoAccent, width: 2),
                      ),
                    ),
                  ),
                ),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
                border: Border.all(color: Colors.white10),
              ),
              child: Center(
                child: Icon(
                  _getStatusIcon(),
                  size: 48,
                  color: Colors.indigoAccent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _getStatusIcon() {
    switch (widget.status) {
      case VoiceCoachStatus.listening: return Icons.graphic_eq;
      case VoiceCoachStatus.processing: return Icons.hourglass_empty;
      case VoiceCoachStatus.speaking: return Icons.volume_up;
      case VoiceCoachStatus.success: return Icons.check_circle_outline;
      default: return Icons.bubble_chart;
    }
  }
}
