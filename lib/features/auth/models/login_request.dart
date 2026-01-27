class LoginRequest {
  final String usuario;
  final String clave;
  final String idSistema;

  LoginRequest({
    required this.usuario,
    required this.clave,
    required this.idSistema,
  });

  Map<String, dynamic> toJson() {
    return {
      'usuario': usuario,
      'clave': clave,
      'id_sistema': int.tryParse(idSistema) ?? 0,
    };
  }
}