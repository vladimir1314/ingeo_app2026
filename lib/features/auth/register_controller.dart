import 'package:ingeo_app/core/services/http_provider.dart';

class RegisterController {
  final HttpProvider _httpProvider = HttpProvider();

  Future<dynamic> solicitudNewUser(Map<String, dynamic> request) async {
    try {
      // Endpoint: /suite/admin/newuser
      final response = await _httpProvider.post(
        '/security/usuario/sistema/movil',
        body: request,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }
}
