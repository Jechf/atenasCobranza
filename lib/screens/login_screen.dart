import 'dart:convert';
import '../config.dart';
import '../home_screen.dart';
import 'package:uuid/uuid.dart';
import '../session_manager.dart';
import 'package:flutter/material.dart';
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
  bool _rememberMe = false;
  String _errorMessage = '';
  String _deviceId = '';
  String _location = '';

  List<dynamic> moneda = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initializeDeviceAndLocation();
    _loadSavedCredentials();
  }

  // Cargar credenciales guardadas
  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUsername = prefs.getString('saved_username');
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (savedUsername != null && rememberMe) {
        setState(() {
          _usernameController.text = savedUsername;
          _rememberMe = rememberMe;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved credentials: $e');
    }
  }

  // Guardar o eliminar credenciales según la opción "Recordar usuario"
  Future<void> _saveOrRemoveCredentials() async {
    final prefs = await SharedPreferences.getInstance();

    if (_rememberMe) {
      await prefs.setString('saved_username', _usernameController.text);
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('saved_username');
      await prefs.setBool('remember_me', false);
    }
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

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // Guardar o eliminar credenciales según la preferencia
    await _saveOrRemoveCredentials();

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

        moneda = List<dynamic>.from(data['data']?['moneda'] ?? []);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cobradorId', cobrador['id']);
        await prefs.setString('nombre', cobrador['nombre']);
        await prefs.setString('cedula', cobrador['token']);
        await prefs.setString('usuario', data['usuario']);
        await prefs.setString('db', data['db']);
        final String bancaFromResponse = data['data']['banca'].toString();
        await prefs.setString('banca', bancaFromResponse);

        // debugPrint('Banca guardada: $bancaFromResponse');

        // Inicializar y registrar la sesión
        await SessionManager().initialize();
        await SessionManager().registerUserInteraction();

        final usuario = prefs.getString('usuario') ?? '';
        final db = prefs.getString('db') ?? '';
        final banca = prefs.getString('banca');

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (context) => HomeScreen(
                    cobrador: cobrador,
                    moneda: moneda,
                    usuario: usuario,
                    db: db,
                    banca: banca,
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
                    SizedBox(height: 10),
                    // Checkbox para recordar usuario
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (bool? value) {
                            setState(() {
                              _rememberMe = value ?? false;
                            });
                          },
                        ),
                        Text('Recordar usuario'),
                      ],
                    ),
                    SizedBox(height: 10),
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
                          'ID: ${_deviceId.length >= 6 ? _deviceId.substring(_deviceId.length - 6) : _deviceId}',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
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
