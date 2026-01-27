import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ingeo_app/core/access_control/access_control_service.dart';
import 'package:ingeo_app/core/access_control/app_features.dart';
import 'package:ingeo_app/features/geolocation/geolocation_screen.dart';
import 'package:ingeo_app/features/overlap/overlap_screen.dart';
import 'package:ingeo_app/features/auth/login_screen.dart';
import 'package:ingeo_app/utils/pending_file_handler.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Verificar estado de autenticación al iniciar
    AccessControlService().checkAuthStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingFile();
      PendingFileHandler().pendingFilePath.addListener(_checkPendingFile);
    });
  }

  @override
  void dispose() {
    PendingFileHandler().pendingFilePath.removeListener(_checkPendingFile);
    super.dispose();
  }

  void _checkPendingFile() {
    if (PendingFileHandler().pendingFilePath.value != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GeolocationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DashboardOption> options = [
      DashboardOption(
        title: 'Geolocalización',
        description:
            'Plataforma integral de cartografía digital y captura de datos georreferenciados, que permite el análisis territorial avanzado mediante la integración de capas oficiales en tiempo real.',
        icon: Icons.location_on,
        backgroundColor: const Color(0xFF008E12),
        textColor: Colors.white,
        isAvailable: true,
        feature: AppFeature.geolocation,
      ),
      DashboardOption(
        title: 'Análisis de Superposición',
        description:
            'Validación territorial inmediata para la optimización de decisiones técnicas mediante el cruce de datos de campo y capas oficiales en tiempo real.',
        icon: Icons.layers,
        backgroundColor: const Color(0xFFE21818),
        textColor: Colors.white,
        isAvailable: true,
        feature: AppFeature.overlapAnalysis,
      ),
      DashboardOption(
        title: 'Libreta D\'Campo',
        description: 'Registra hallazgos y evidencias',
        icon: Icons.book,
        backgroundColor: const Color(0xFF0097BD),
        textColor: Colors.white,
        isAvailable: false,
        feature: AppFeature.fieldNotebook,
      ),
      DashboardOption(
        title: 'Encuentra tu punto (AquiSitoNo+)',
        description: 'Localiza y comparte ubicaciones',
        icon: Icons.place,
        backgroundColor: const Color(0xFFB06000),
        textColor: Colors.white,
        isAvailable: false,
        feature: AppFeature.findMyPoint,
      ),
      DashboardOption(
        title: 'Análisis GIS Básico',
        description: 'Herramientas esenciales de GIS',
        icon: Icons.map,
        backgroundColor: const Color(0xFFA6A09B),
        textColor: Colors.white,
        isAvailable: false,
        feature: AppFeature.gisAnalysisBasic,
      ),
      DashboardOption(
        title: 'Análisis GIS Intermedio',
        description: 'Consultas y visualización avanzada',
        icon: Icons.analytics,
        backgroundColor: const Color(0xFF44403B),
        textColor: Colors.white,
        isAvailable: false,
        feature: AppFeature.gisAnalysisIntermediate,
      ),
      DashboardOption(
        title: 'Cronograma D\'MiTrabajo',
        description: 'Planifica actividades y tareas',
        icon: Icons.calendar_today,
        backgroundColor: const Color(0xFF6A7F00),
        textColor: Colors.white,
        isAvailable: false,
        feature: AppFeature.workSchedule,
      ),
      DashboardOption(
        title: 'Administrar mi BD',
        description: 'Gestiona tu base de datos',
        icon: Icons.storage,
        backgroundColor: const Color(0xFF009570),
        textColor: Colors.white,
        isAvailable: false,
        feature: AppFeature.manageDb,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, color: Colors.teal),
            SizedBox(width: 8),
            Text('InGeo', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 42,
                      height: 42,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Transforma datos de campo en decisiones estratégicas con geolocalización avanzada y Gestiona la viabilidad geográfica de tus proyectos en tiempo real con precisión técnica y datos oficiales.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16.0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16.0,
                  mainAxisSpacing: 16.0,
                  childAspectRatio: 0.9,
                ),
                itemCount: options.length,
                itemBuilder: (context, index) =>
                    DashboardCard(option: options[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardOption {
  final String title;
  final String description;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;
  final bool isAvailable;
  final AppFeature feature;

  DashboardOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
    required this.isAvailable,
    required this.feature,
  });
}

class DashboardCard extends StatelessWidget {
  final DashboardOption option;

  const DashboardCard({super.key, required this.option});

  void _navigateToFeature(BuildContext context, AppFeature feature) {
    if (feature == AppFeature.geolocation) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const GeolocationScreen(),
        ),
      );
    } else if (feature == AppFeature.overlapAnalysis) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OverlapScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AccessControlService().isAuthenticated,
      builder: (context, isAuth, child) {
        final hasAccess = AccessControlService().canAccess(option.feature);

        final isDisabled = !option.isAvailable;
        final isLocked = !hasAccess && !isDisabled;

        final cardColor = isDisabled
            ? Colors.grey.shade400
            : isLocked
            ? option.backgroundColor.withOpacity(0.9)
            : option.backgroundColor;

        final textColor = isDisabled ? Colors.black54 : option.textColor;

        return InkWell(
          onTap: (isDisabled)
              ? null
              : () {
                  if (isLocked) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LoginScreen(
                          onLoginSuccess: () =>
                              _navigateToFeature(context, option.feature),
                        ),
                      ),
                    );
                    return;
                  }
                  _navigateToFeature(context, option.feature);
                },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Icon(
                    option.icon,
                    size: 120,
                    color: (isDisabled ? Colors.black : Colors.white)
                        .withOpacity(0.08),
                  ),
                ),

                // Banner "Próximamente"
                if (isDisabled)
                  Positioned(
                    top: 14,
                    right: -44,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: -math.pi / 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 44,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade700.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PRÓXIMAMENTE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Contenido
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(option.icon, color: textColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        option.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          option.description,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 10,
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor.withOpacity(0.9),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Candado (opcional UX)
                if (isLocked)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
