import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class AgenciesMapScreen extends StatefulWidget {
  final List<dynamic> agencies;

  const AgenciesMapScreen({super.key, required this.agencies});

  @override
  _AgenciesMapScreenState createState() => _AgenciesMapScreenState();
}

class _AgenciesMapScreenState extends State<AgenciesMapScreen> {
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  LatLng? _mapCenter;
  LatLng? _myLocation;
  bool _isLoading = true;
  bool _locationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _initializeMapData();
  }

  Future<void> _getMyLocation() async {
    try {
      // Solicitar permisos de ubicación
      final status = await Permission.location.request();

      if (status.isGranted) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        setState(() {
          _myLocation = LatLng(position.latitude, position.longitude);
          _locationPermissionGranted = true;

          // Agregar marcador de mi ubicación
          _markers.add(
            Marker(
              markerId: MarkerId('my_location'),
              position: _myLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue,
              ),
              infoWindow: InfoWindow(title: 'Mi Ubicación'),
              zIndex: 2, // Para que aparezca sobre otros marcadores
            ),
          );

          // Agregar círculo de precisión (opcional)
          _circles.add(
            Circle(
              circleId: CircleId('accuracy_circle'),
              center: _myLocation!,
              radius: 20, // Radio de 20 metros
              fillColor: Colors.blue.withOpacity(0.2),
              strokeColor: Colors.blue,
              strokeWidth: 1,
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
    }
  }

  void _initializeMapData() async {
    if (widget.agencies.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Obtener tu ubicación primero
    await _getMyLocation();

    double totalLat = 0;
    double totalLng = 0;
    int validLocations = 0;

    for (final agency in widget.agencies) {
      final location = agency['ubicacion']?.toString();
      if (location != null &&
          location != '0' &&
          location != '' &&
          !location.contains('ubicaGps')) {
        final coords = _parseLocation(location);
        if (coords != null) {
          _addMarker(agency, coords);
          totalLat += coords.latitude;
          totalLng += coords.longitude;
          validLocations++;
        }
      }
    }

    // Determinar el centro del mapa
    if (_myLocation != null && validLocations > 0) {
      // Centrar entre tu ubicación y el promedio de las agencias
      setState(() {
        _mapCenter = LatLng(
          (_myLocation!.latitude + totalLat / validLocations) / 2,
          (_myLocation!.longitude + totalLng / validLocations) / 2,
        );
        _isLoading = false;
      });
    } else if (validLocations > 0) {
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
      // Validar que no esté vacío y no sea "0"
      if (location.isEmpty || location == '0' || location == '0,0') {
        return null;
      }

      // Validar formato completo (debe tener coma)
      if (!location.contains(',')) {
        debugPrint('Formato inválido: falta coma en ubicación: $location');
        return null;
      }

      final parts = location.split(',');

      // Validar que tenga exactamente 2 partes
      if (parts.length != 2) {
        debugPrint(
          'Formato inválido: debe tener lat y lng separados por coma: $location',
        );
        return null;
      }

      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());

      // Validar que ambos sean números válidos
      if (lat == null || lng == null) {
        debugPrint(
          'Coordenadas no numéricas: lat=$lat, lng=$lng en: $location',
        );
        return null;
      }

      // Validar rangos geográficos
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        debugPrint('Coordenadas fuera de rango: lat=$lat, lng=$lng');
        return null;
      }

      // Validar que no sean coordenadas (0,0) - usualmente indica error
      if (lat == 0 && lng == 0) {
        debugPrint('Coordenadas (0,0) - probablemente error: $location');
        return null;
      }

      return LatLng(lat, lng);
    } catch (e) {
      debugPrint('Error parsing location: $e - Ubicación: $location');
      return null;
    }
  }

  void _addMarker(Map<String, dynamic> agency, LatLng position) {
    final isCobrar = agency['estado'] == true;
    final markerColor =
        isCobrar ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed;

    _markers.add(
      Marker(
        markerId: MarkerId(agency['codigo'].toString()),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
        infoWindow: InfoWindow(
          title: agency['nombre']?.toString() ?? 'Agencia sin nombre',
          snippet: 'Código: ${agency['codigo']}',
          onTap: () => _openInGoogleMaps(position),
        ),
        zIndex: 1,
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
        actions: [
          if (_locationPermissionGranted)
            IconButton(
              icon: Icon(Icons.my_location, color: Colors.white),
              onPressed: () {
                if (_myLocation != null) {
                  _mapController.animateCamera(
                    CameraUpdate.newLatLngZoom(_myLocation!, 15),
                  );
                }
              },
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _mapCenter == null
              ? const Center(child: Text('No hay ubicaciones disponibles'))
              : Stack(
                children: [
                  GoogleMap(
                    onMapCreated: (controller) => _mapController = controller,
                    initialCameraPosition: CameraPosition(
                      target: _mapCenter!,
                      zoom: 12.0,
                    ),
                    markers: _markers,
                    circles: _circles,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: true,
                  ),

                  // Botón de centrado manual
                  if (_locationPermissionGranted)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Color(0xFF1A1B41),
                        onPressed: () {
                          if (_myLocation != null) {
                            _mapController.animateCamera(
                              CameraUpdate.newLatLngZoom(_myLocation!, 15),
                            );
                          }
                        },
                        child: Icon(Icons.my_location, color: Colors.white),
                      ),
                    ),
                ],
              ),
    );
  }
}
