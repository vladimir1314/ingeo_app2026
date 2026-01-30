import 'package:flutter/foundation.dart';
import 'package:ingeo_app/core/storage/secure_storage.dart';
import 'app_features.dart';

class AccessControlService {
  static final AccessControlService _instance =
      AccessControlService._internal();
  factory AccessControlService() => _instance;
  AccessControlService._internal();

  final ValueNotifier<bool> isAuthenticated = ValueNotifier(false);

  /// Inicializa el estado de autenticación leyendo el almacenamiento seguro
  Future<void> checkAuthStatus() async {
    final token = await SecureStorage.getToken();
    isAuthenticated.value = token != null && token.isNotEmpty;
  }

  /// Actualiza el estado manualmente (usar después de login/logout)
  void updateAuthStatus(bool isAuth) {
    isAuthenticated.value = isAuth;
  }

  /// Verifica si el usuario tiene acceso a una funcionalidad específica
  bool canAccess(AppFeature feature) {
    // Si no está autenticado, verificamos qué funciones requieren login
    if (!isAuthenticated.value) {
      switch (feature) {
        //case AppFeature.overlapAnalysis:
        case AppFeature.fieldNotebook:
        case AppFeature.manageDb:
        case AppFeature.workSchedule:
        case AppFeature.trackRecording:
          return false;
        // Agrega aquí más casos según sea necesario
        default:
          return true;
      }
    }

    // Si está autenticado, por ahora tiene acceso a todo
    // Aquí se podría expandir para verificar roles o planes
    return true;
  }
}
