import 'package:ingeo_app/core/config/app_config.dart';
import 'package:ingeo_app/core/services/http_provider.dart';
import 'package:ingeo_app/core/storage/secure_storage.dart';
import 'package:ingeo_app/features/auth/models/login_request.dart';

class LoginController {
  final HttpProvider _httpProvider = HttpProvider();

  Future<bool> login(String username, String password) async {
    try {
      final request = LoginRequest(
        usuario: username,
        clave: password,
        idSistema: AppConfig.idSistema,
      );

      // El endpoint debe comenzar sin barra inicial si baseUrl no termina en barra,
      // pero HttpProvider maneja la concatenación.
      // Asumiendo 'movil/security/singin' como solicitaste.
      final response = await _httpProvider.post(
        'movil/security/singin',
        body: request.toJson(),
      );

      // Validar respuesta exitosa.
      if (response != null && response is Map<String, dynamic>) {
        if (response['status'] == 'success' && response.containsKey('token')) {
          await SecureStorage.saveToken(response['token']);
          return true;
        }
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }
}
