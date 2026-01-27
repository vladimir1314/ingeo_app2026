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
    ]),
    LayerGroup('Ecosistemas Frágiles', [
      LayerItem('Ecosistemas Frágiles', 'sp_ecosistemas_fragiles'),
      LayerItem('Bofedales Inventariados', 'sp_bofedales_inventariados'),
      LayerItem('Bosques Secos', 'sp_bosques_secos'),
    ]),
    LayerGroup('Restos Arqueológicos', [
      LayerItem('Declarados', 'sp_sigda_declarados'),
      LayerItem('Delimitados', 'sp_sigda_delimitados'),
      LayerItem('Qhapaq Ñan', 'sp_sigda_qhapaq_nan'),
    ]),
  ];

  /// Para casos donde quieras TODAS las capas juntas
  static List<LayerGroup> get all => [...geolocationLayers, ...overlapLayers];
}
