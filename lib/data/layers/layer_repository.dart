import 'package:ingeo_app/models/layer_states.dart';

class LayerRepository {
  static final List<LayerGroup> geolocationLayers = [
    LayerGroup('Georreferenciación', [
      LayerItem('Grillas UTM Perú', 'sp_grilla_utm_peru'),
      LayerItem('Centros Poblados INEI', 'sp_centros_poblados_inei'),
    ]),
    LayerGroup('Catastro Rural', [
      LayerItem('Comunidades Campesinas', 'sp_comunidades_campesinas'),
      LayerItem('Comunidades Nativas', 'sp_comunidades_nativas'),
    ]),
    LayerGroup('Límites Políticos', [
      LayerItem('Departamentos', 'sp_departamentos'),
      LayerItem('Provincias', 'sp_provincias'),
      LayerItem('Distritos', 'sp_distritos'),
    ]),
    LayerGroup('Hidrografía', [
      LayerItem('Vertientes', 'sp_vertientes'),
      LayerItem('Cuencas - UH Oficial', 'sp_cuencas'),
      LayerItem('Sub cuencas - UH N5', 'sp_subcuencas'),
      LayerItem('Lagunas', 'sp_lagunas'),
      LayerItem('Ríos Navegables', 'sp_rios_navegables'),
      LayerItem('Ríos Quebradas', 'sp_rios_quebradas'),
    ]),
  ];

  static final List<LayerGroup> overlapLayers = [
    LayerGroup('Áreas Naturales Protegidas', [
      LayerItem('ANP Nacional Definidas', 'sp_anp_nacionales_definidas'),
      LayerItem('Zonas Amortiguamiento', 'sp_zonas_amortiguamiento'),
      LayerItem('Zonas Reservadas', 'sp_zonas_reservadas'),
      LayerItem(
        'Áreas de Conservación Regional',
        'sp_areas_conservacion_regional',
      ),
      LayerItem(
        'Áreas de Conservación Privada',
        'sp_areas_conservacion_privada',
      ),
      LayerItem('Zonificación ANP', 'sp_zonificacion_anp'),
      LayerItem('Zonificación ACR', 'sp_zonificacion_acr'),
      LayerItem('Zonificación ACP', 'sp_zonificacion_acp'),
    ]),

    LayerGroup('Ecosistemas Frágiles', [
      LayerItem('Ecosistemas Frágiles', 'sp_ecosistemas_fragiles'),
      LayerItem('Bofedales Inventariados', 'sp_bofedales_inventariados'),
      LayerItem('Bosques Secos', 'sp_bosques_secos'),
      LayerItem('Habitat Críticos', 'sp_habitat_criticos_serfor'),
    ]),
    LayerGroup('Restos Arqueológicos', [
      LayerItem('Declarados', 'sp_sigda_declarados'),
      LayerItem('Delimitados', 'sp_sigda_delimitados'),
      LayerItem('Qhapaq Ñan', 'sp_sigda_qhapaq_nan'),
      LayerItem('Población Afroperuana', 'sp_pob_afroperuana'),
      LayerItem('CIRAS Emitidos', 'sp_ciras_emitidos'),
      LayerItem(
        'Localidades Pertenecientes a Pueblos Indígenas',
        'sp_localidad_pertenecientes_pueblos_indigenas',
      ),
      LayerItem('BIP UBIGEO', 'sp_bip_ubigeo'),
    ]),

    LayerGroup('Peligros Geológicos', [
      LayerItem('Peligros Geológicos', 'sp_peligrosgeologicos'),
      LayerItem('Zonas Críticas', 'sp_zonas_criticas'),
      LayerItem(
        'Cartografia Peligros Fotointerpretado',
        'sp_cartografia_peligros_fotointerpretado',
      ),
      LayerItem(
        'Zonas Críticas FEN-2023-2024',
        'sp_zonas_criticas_fen_2023_2024',
      ),
    ]),

    LayerGroup('Ordenamiento Forestal', [
      LayerItem(
        'Bosque Local con Titulo Habilitante',
        'sp_bosque_local_titulo_habilitante',
      ),
      LayerItem(
        'Bosques de Producción Permanente',
        'sp_bosques_produccion_permanente',
      ),
      LayerItem('Bosques Protectores', 'sp_bosques_protectores'),
      LayerItem('Cesiones de Uso', 'sp_cesiones_uso'),
      LayerItem('Concesiones Forestales', 'sp_concesiones_forestales'),
      LayerItem('Unidad Aprovechamiento', 'sp_unidad_aprovechamiento'),
    ]),
    LayerGroup('Catastro Minero', [
      LayerItem('Catastro Minero Z17', 'sp_catastro_minero_z17'),
      LayerItem('Catastro Minero Z18', 'sp_catastro_minero_z18'),
      LayerItem('Catastro Minero Z19', 'sp_catastro_minero_z19'),
    ]),
  ];

  /// Para casos donde quieras TODAS las capas juntas
  static List<LayerGroup> get all => [...geolocationLayers, ...overlapLayers];
}
