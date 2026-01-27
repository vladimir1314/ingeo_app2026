import 'dart:async';

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OSMPlace {
  final String displayName;
  final String lat;
  final String lon;
  final String? type;
  final String? country;
  final Map<String, dynamic>? address;

  OSMPlace({
    required this.displayName,
    required this.lat,
    required this.lon,
    this.type,
    this.country,
    this.address,
  });

  factory OSMPlace.fromJson(Map<String, dynamic> json) {
    return OSMPlace(
      displayName: json['display_name'] ?? '',
      lat: json['lat'] ?? '0',
      lon: json['lon'] ?? '0',
      type: json['type'],
      country: json['address']?['country'],
      address: json['address'] as Map<String, dynamic>?,
    );
  }

  String get formattedAddress {
    if (address == null) return displayName;

    final List<String> parts = [];
    if (address!['road'] != null) parts.add(address!['road']);
    if (address!['city'] != null) parts.add(address!['city']);
    if (address!['state'] != null) parts.add(address!['state']);
    if (address!['country'] != null) parts.add(address!['country']);

    return parts.isNotEmpty ? parts.join(', ') : displayName;
  }
}

Future<List<OSMPlace>> _fetchOSMResults(String query) async {
  final uri = Uri.parse(
    'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=10',
  );
  final response = await http.get(uri, headers: {
    'User-Agent': 'flutter_app', // Nominatim requiere un User-Agent
  });

  if (response.statusCode == 200) {
    final List data = json.decode(response.body);
    return data.map((e) => OSMPlace.fromJson(e)).toList();
  } else {
    return [];
  }
}

class CustomSearchBar extends StatefulWidget {
  final Function(LatLng) onLocationSelected;

  const CustomSearchBar({
    super.key,
    required this.onLocationSelected,
  });

  @override
  State<CustomSearchBar> createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar> {
  bool isSearchExpanded = true;
  final TextEditingController _searchController = TextEditingController();
  List<Location> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  List<OSMPlace> _osmResults = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchLocation(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
        });
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final results = await _fetchOSMResults(query);
        setState(() {
          _osmResults = results;
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _osmResults = [];
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Obtenemos el ancho de la pantalla
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: screenWidth,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF42887C).withOpacity(0.6),
            borderRadius: BorderRadius.circular(50), // 🔹 redondeado 50%
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: isSearchExpanded
              ? TextField(
                  controller: _searchController,
                  onChanged: _searchLocation,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    height: 1.0,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar lugares',
                    prefixIcon: const Icon(Icons.search),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              isSearchExpanded = false;
                              _searchController.clear();
                              _searchResults = [];
                            });
                          },
                        ),
                      ],
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 0,
                    ),
                    isDense: true,
                  ),
                )
              : TextButton.icon(
                  onPressed: () {
                    setState(() {
                      isSearchExpanded = true;
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(
                    Icons.search,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    'Buscar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
        ),
        if (_osmResults.isNotEmpty && isSearchExpanded)
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            width: screenWidth,
            // Mismo ancho que el campo de búsqueda expandido
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _osmResults.length,
              itemBuilder: (context, index) {
                final place = _osmResults[index];
                return ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(
                    place.formattedAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${place.lat}, ${place.lon}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    final lat = double.tryParse(place.lat) ?? 0.0;
                    final lon = double.tryParse(place.lon) ?? 0.0;
                    widget.onLocationSelected(LatLng(lat, lon));
                    setState(() {
                      _osmResults = [];
                      _searchController.clear();
                      isSearchExpanded = false;
                    });
                  },
                );
              },
            ),
          )
      ],
    );
  }
}
