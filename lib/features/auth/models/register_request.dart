class RegisterRequest {
  final String cUsuario;
  final String cDni;
  final String cNombres;
  final String cApePaterno;
  final String cApeMaterno;
  final String cEmail;
  final String cCelular;
  final String idRol;
  final int nNivelAcceso;
  final String idSistema;

  RegisterRequest({
    required this.cUsuario,
    required this.cDni,
    required this.cNombres,
    required this.cApePaterno,
    required this.cApeMaterno,
    required this.cEmail,
    required this.cCelular,
    this.idRol = "132",
    this.nNivelAcceso = 1,
    required this.idSistema,
  });

  Map<String, dynamic> toJson() {
    return {
      "c_usuario": cUsuario,
      "c_dni": cDni,
      "c_nombres": cNombres,
      "c_ape_paterno": cApePaterno,
      "c_ape_materno": cApeMaterno,
      "c_email": cEmail,
      "c_celular": cCelular,
      "id_rol": idRol,
      "n_nivel_acceso": nNivelAcceso,
      "id_sistema": idSistema,
    };
  }
}