import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AgenciesMapScreen extends StatefulWidget {
  final List<dynamic> agencies;

  const AgenciesMapScreen({super.key, required this.agencies});

  @override
  _AgenciesMapScreenState createState() => _AgenciesMapScreenState();
}

class _AgenciesMapScreenState extends State<AgenciesMapScreen> {
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  LatLng? _mapCenter;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeMapData();
  }

  void _initializeMapData() {
    if (widget.agencies.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    double totalLat = 0;
    double totalLng = 0;
    int validLocations = 0;

    for (final agency in widget.agencies) {
      final location = agency['ubicacion']?.toString();
      if (location != null && location != '0') {
        final coords = _parseLocation(location);
        if (coords != null) {
          _addMarker(agency, coords);
          totalLat += coords.latitude;
          totalLng += coords.longitude;
          validLocations++;
        }
      }
    }

    if (validLocations > 0) {
      setState(() {
        _mapCenter = LatLng(
          totalLat / validLocations,
          totalLng / validLocations,
        );
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  LatLng? _parseLocation(String location) {
    try {
      final parts = location.split(',');
      if (parts.length != 2) return null;

      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());

      return (lat != null && lng != null) ? LatLng(lat, lng) : null;
    } catch (e) {
      debugPrint('Error parsing location: $e');
      return null;
    }
  }

  void _addMarker(Map<String, dynamic> agency, LatLng position) {
    _markers.add(
      Marker(
        markerId: MarkerId(agency['codigo'].toString()),
        position: position,
        infoWindow: InfoWindow(
          title: agency['nombre']?.toString() ?? 'Agencia sin nombre',
          snippet: 'Código: ${agency['codigo']}',
          onTap: () => _openInGoogleMaps(position),
        ),
      ),
    );
  }

  Future<void> _openInGoogleMaps(LatLng position) async {
    final url =
        'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir Google Maps')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mapa de Agencias',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1A1B41),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _mapCenter == null
              ? const Center(child: Text('No hay ubicaciones disponibles'))
              : GoogleMap(
                onMapCreated: (controller) => _mapController = controller,
                initialCameraPosition: CameraPosition(
                  target: _mapCenter!,
                  zoom: 12.0,
                ),
                markers: _markers,
              ),
    );
  }
}
