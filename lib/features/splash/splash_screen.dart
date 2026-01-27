import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ingeo_app/features/dashboard_screen.dart';
import 'package:video_player/video_player.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _videoError = false;
  bool _isTransitioning = false;
  late Future<void> _initializeVideoFuture;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();

    // Iniciar ambos procesos simultáneamente
    _initializeVideoFuture = _initializeVideo();

    // Timeout por si el video tarda demasiado
    _startTimeout();
  }

  Future<void> _initializeVideo() async {
    try {
      // Usar paquete que soporta más formatos y es más eficiente
      _controller = VideoPlayerController.asset(
        'assets/splash/splash_video.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      // Inicializar con timeout
      await _controller.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Video initialization timeout');
        },
      );

      if (!mounted) return;

      setState(() {
        _initialized = true;
        _videoError = false;
      });

      // Configurar listener para el final del video
      _controller.addListener(_checkVideoEnd);

      // Reproducir el video
      await _controller.play();

      // Cancelar timeout si el video se inicializó correctamente
      _timeoutTimer?.cancel();
    } catch (e) {
      debugPrint('Error initializing video: $e');

      if (mounted) {
        setState(() {
          _videoError = true;
        });

        // Ir al dashboard después de un breve delay
        Future.delayed(const Duration(milliseconds: 500), _goNext);
      }
    }
  }

  void _startTimeout() {
    // Ir al dashboard después de 2.5 segundos máximo
    _timeoutTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!_isTransitioning && mounted) {
        _goNext();
      }
    });
  }

  void _checkVideoEnd() {
    // Si el video terminó o hay un error, ir al siguiente screen
    if (_controller.value.isInitialized &&
        _controller.value.position >= _controller.value.duration) {
      _goNext();
    }

    // También ir al siguiente si hay error en la reproducción
    if (_controller.value.hasError) {
      _goNext();
    }
  }

  void _goNext() {
    if (_isTransitioning) return;

    _isTransitioning = true;
    _timeoutTimer?.cancel();
    _controller.removeListener(_checkVideoEnd);

    // Usar un fade transition más suave
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DashboardScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.removeListener(_checkVideoEnd);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video player
          if (_initialized && !_videoError)
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),

          // Loading indicator mientras se inicializa
          if (!_initialized && !_videoError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cargando...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

          // Botón de skip para el usuario (opcional)
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            right: 20,
            child: GestureDetector(
              onTap: _goNext,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Saltar',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
