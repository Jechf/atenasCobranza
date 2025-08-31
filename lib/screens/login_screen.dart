import 'dart:convert';
import '../config.dart';
import '../home_screen.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> getOrCreateDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'unique_device_id';
  final storedId = prefs.getString(key);

  if (storedId != null) {
    return storedId;
  } else {
    final newId =
        const Uuid().v4(); // Ej: "2f1c9dc0-2e5f-4f4e-a123-bfcb0f8b9b17"
    await prefs.setString(key, newId);
    return newId;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  String _deviceId = '';
  String _location = '';

  List<dynamic> monedas = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initializeDeviceAndLocation();
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.phone.request();
  }

  Future<void> _initializeDeviceAndLocation() async {
    await _fetchDeviceId();
    await _fetchLocation();
  }

  Future<void> _fetchDeviceId() async {
    try {
      final uuid = await getOrCreateDeviceId();
      setState(() {
        _deviceId = uuid;
        debugPrint("");
        debugPrint('Device UUID: $_deviceId');
        debugPrint("");
      });
    } catch (e) {
      setState(() {
        _deviceId = 'Error al obtener el ID';
      });
    }
  }

  Future<void> _fetchLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _location = 'GPS desactivado';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _location = 'Permiso denegado';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _location = 'Permiso denegado permanentemente';
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _location = '${position.latitude}, ${position.longitude}';
      });
    } catch (e) {
      setState(() {
        _location = 'Error al obtener la ubicación';
      });
    }
  }

  // Función para copiar el device ID al portapapeles
  Future<void> _copyDeviceIdToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Device ID copiado al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final body = json.encode({
      'usuario': _usernameController.text,
      'clave': _passwordController.text,
      'device': _deviceId,
    });

    final response = await http.post(
      Uri.parse('${Config.apiUrl}login'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    final data = json.decode(response.body);

    try {
      if (data['e'] == 1) {
        final cobrador = {
          'id': data['id']?.toString() ?? '',
          'nombre': data['data']?['nombre'] ?? '',
          'token': data['data']?['cedula'] ?? '',
        };

        monedas = List<dynamic>.from(data['data']?['monedas'] ?? []);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cobradorId', cobrador['id']);
        await prefs.setString('nombre', cobrador['nombre']);
        await prefs.setString('cedula', cobrador['token']);
        await prefs.setString('usuario', data['usuario']);
        await prefs.setString('db', data['db']);

        final usuario = prefs.getString('usuario') ?? '';
        final db = prefs.getString('db') ?? '';

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (context) => HomeScreen(
                    cobrador: cobrador,
                    monedas: monedas,
                    usuario: usuario,
                    db: db,
                  ),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = data['mensaje'] ?? 'Error en la autenticación';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error en la APP. Intenta de nuevo más tarde.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  'assets/icon/fondo_login.jpg',
                ), // Ruta de tu imagen
                fit: BoxFit.cover, // Cubre todo el espacio disponible
              ),
            ),
          ),

          // Contenedor de inicio de sesión
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Container(
                padding: EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 255, 255),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon/logo.png',
                      width: 100,
                      height: 100,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Iniciar Sesión',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Usuario',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 20),
                    _isLoading
                        ? CircularProgressIndicator()
                        : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: 50,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: Color.fromARGB(224, 26, 27, 65),
                          ),
                          child: Text(
                            'Ingresar',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                    if (_errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          _errorMessage,
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    SizedBox(height: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ID: $_deviceId',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.content_copy,
                                size: 16,
                                color: Color.fromARGB(224, 26, 27, 65),
                              ),
                              onPressed: _copyDeviceIdToClipboard,
                              tooltip: 'Copiar Device ID',
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              iconSize: 16,
                            ),
                            Text("Copiar ID"),
                          ],
                        ),
                      ],
                    ),
                    // Text(
                    //   'Ubicación: $_location',
                    //   style: TextStyle(fontSize: 12, color: Colors.grey),
                    // ),
                    SizedBox(height: 8),
                    Text(
                      'V.1.0.0',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
