import 'package:turf/turf.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final p1 = Position.named(lng: -74.9463, lat: -9.7786);
  final p2 = Position.named(lng: -74.9400, lat: -9.7786);
  final p3 = Position.named(lng: -74.9400, lat: -9.7700);
  final p4 = Position.named(lng: -74.9463, lat: -9.7700);
  final p5 = Position.named(lng: -74.9463, lat: -9.7786);
  
  final polygon = Polygon(coordinates: [[p1, p2, p3, p4, p5]]);
  print('Area: ${area(polygon)}');
}