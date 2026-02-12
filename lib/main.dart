import 'package:flutter/material.dart';
import 'package:ingeo_app/core/config/app_config.dart';

import 'dart:io';
import 'package:ingeo_app/core/config/http_overrides.dart';
import 'package:ingeo_app/features/splash/splash_screen.dart';
import 'package:ingeo_app/utils/pending_file_handler.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

void main() async {
  HttpOverrides.global = BadCertificateHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initializeDeepLinks();
  }

  Future<void> _initializeDeepLinks() async {
    // Manejar archivo inicial (cuando la app se abre desde un archivo)
    _handleInitialUri();

    // Escuchar nuevos archivos (cuando la app ya está abierta)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        _handleIncomingUri(uri);
      },
      onError: (err) {
        debugPrint('Error al recibir URI: $err');
      },
    );
  }

  Future<void> _handleInitialUri() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        _handleIncomingUri(uri);
      }
    } catch (e) {
      debugPrint('Error al obtener URI inicial: $e');
    }
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    debugPrint('URI recibido: $uri');

    String? filePath;

    // Extraer la ruta del archivo según el esquema
    if (uri.scheme == 'file') {
      filePath = uri.path;
    } else if (uri.scheme == 'content') {
      filePath = uri.toString(); // Pasar el URI completo
    }

    if (filePath != null) {
      // Si es content scheme, lo dejamos pasar para que ImportLayersUtil intente detectar el tipo
      // Si es file scheme, verificamos la extensión
      if (uri.scheme == 'content' || _isKmlOrKmzFile(filePath)) {
        PendingFileHandler().setPendingFile(filePath);
      }
    }
  }

  bool _isKmlOrKmzFile(String path) {
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.kml') || lowerPath.endsWith('.kmz');
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'InGeoApp',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const SplashScreen(),
    );
  }
}
