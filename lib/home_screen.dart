import 'dart:io';
import 'dart:async';
import 'config.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

Future<String> getOrCreateDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'unique_device_id';
  final storedId = prefs.getString(key);

  if (storedId != null) {
    return storedId;
  } else {
    final newId = const Uuid().v4();
    await prefs.setString(key, newId);
    return newId;
  }
}

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> cobrador;
  final List<dynamic> monedas;
  final String usuario;
  final String db;

  const HomeScreen({
    super.key,
    required this.cobrador,
    required this.monedas,
    required this.usuario,
    required this.db,
  });

  @override
  // ignore: library_private_types_in_public_api
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> zonas = [];
  List<dynamic> agencias = [];

  String? selectedZonaId;
  String? selectedAgenciaId;
  String? nombreAgenciaSeleccionada;
  String _deviceId = '';
  String _location = '0';
  String? selectedMoneda;
  String? saldo;
  String? _numeroTicket;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _montoController = TextEditingController();
  final TextEditingController _fechaController = TextEditingController();
  final TextEditingController _explicacionController = TextEditingController();
  final TextEditingController _codigoController =
      TextEditingController(); // Controlador para el código
  final TextEditingController _novedadController = TextEditingController();

  File? _fotoMontoCero;

  bool isLoadingSaldo = false;
  bool _isSubmitting = false;
  bool _isMontoConfirmed = false; // Estado del checkbox
  bool _isPrinterConnected = false;
  bool _mostrarFormularioMontoCero = false;
  bool _isMontoCero = false;

  File? _selectedImage;

  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initializeDeviceAndLocation();
    _fetchZonas();
    _checkBluetoothConnection();
    _setDefaultDate();
    _monedasList();
  }

  Future<void> _checkBluetoothConnection() async {
    try {
      bool isConnected = await bluetooth.isConnected ?? false;
      setState(() {
        _isPrinterConnected = isConnected;
      });
    } catch (e) {
      setState(() {
        _isPrinterConnected = false;
      });
    }
  }

  void _monedasList() {
    selectedMoneda = widget.monedas[0];
  }

  void _mostrarModal(
    String? agencia,
    String zona,
    String monto,
    String deviceId,
    String fecha,
    String moneda,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 8,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.of(context).size.height *
                  0.8, // 80% de la altura de la pantalla
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Encabezado con icono
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFF1A1B41).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.receipt_long,
                        size: 32,
                        color: Color(0xFF1A1B41),
                      ),
                    ),
                    SizedBox(height: 16),

                    // Título
                    Text(
                      "COMPROBANTE DE COBRO",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1B41),
                      ),
                    ),
                    SizedBox(height: 24),

                    // Datos en formato tabla
                    _buildInfoRow("Agencia:", agencia ?? 'No especificada'),
                    _buildInfoRow("Zona:", zona),
                    SizedBox(height: 16),

                    // Monto destacado
                    Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            "MONTO ABONADO",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "$monto $selectedMoneda",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),

                    _buildInfoRow("Fecha:", fecha),
                    _buildInfoRow("Cobrador:", widget.cobrador['nombre']),
                    SizedBox(height: 24),

                    // Campo de novedad (si aplica)
                    if (!_isMontoCero)
                      TextField(
                        controller: _novedadController,
                        maxLength: 160,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: "Novedad (opcional)",
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF6290C3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                    if (!_isMontoCero) SizedBox(height: 24),

                    // Botones de acción
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Color(0xFF1A1B41)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              "Cancelar",
                              style: TextStyle(color: Color(0xFF1A1B41)),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1A1B41),
                              padding: EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _enviarCobroConNovedad();
                            },
                            child: Text(
                              "Confirmar",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Método auxiliar para construir filas de información
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setDefaultDate() {
    DateTime now = DateTime.now();
    DateTime lastSunday = now.subtract(Duration(days: now.weekday));
    String formattedDate = DateFormat('yyyy-MM-dd').format(lastSunday);
    _fechaController.text = formattedDate;
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(Duration(days: 30)),
      lastDate: DateTime.now(),
      cancelText: "Cancelar",
      helpText: "Selecciona una fecha",
    );

    if (pickedDate != null) {
      String formattedDate = DateFormat('yyyy-MM-dd').format(pickedDate);
      setState(() {
        _fechaController.text = formattedDate;
      });
    }
  }

  Future<void> _requestPermissions() async {
    // Solicitar permisos para ubicación
    var locationStatus = await Permission.location.request();
    if (!locationStatus.isGranted) {
      // Maneja el caso cuando el usuario no concede el permiso
    }

    var phoneStateStatus = await Permission.phone.request();
    if (!phoneStateStatus.isGranted) {
      // Maneja el caso cuando el usuario no concede el permiso
    }

    var cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      // Maneja el caso cuando el usuario no concede el permiso
    }
  }

  Future<void> _initializeDeviceAndLocation() async {
    await _fetchDeviceId();
    await _fetchLocation();
  }

  // ignore: unused_element
  Future<void> _requestCameraPermission() async {
    await Permission.camera.request();
  }

  Future<void> _fetchDeviceId() async {
    try {
      final uuid = await getOrCreateDeviceId();
      setState(() {
        _deviceId = uuid;
        print('UUID persistente desde Home: $_deviceId');
      });
    } catch (e) {
      setState(() {
        _deviceId = 'Error al obtener el ID';
      });
    }
  }

  Future<bool> _checkPrinterConnection() async {
    // Instancia del plugin
    BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

    // Verificar si hay dispositivos conectados
    bool isConnected = await bluetooth.isConnected ?? false;

    return isConnected;
  }

  Future<void> _printReceipt(String mensaje) async {
    BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

    if (await bluetooth.isConnected ?? false) {
      bluetooth.printNewLine();
      bluetooth.printCustom(
        'Monto Recibido',
        2,
        1,
      ); // Texto, tamaño, alineación
      bluetooth.printNewLine();
      bluetooth.printCustom(
        mensaje,
        1,
        0,
      ); // Texto, tamaño, alineación izquierda
      bluetooth.printNewLine();
      bluetooth.printCustom('Gracias por su pago', 1, 1); // Alineado al centro
      bluetooth.printNewLine();
      bluetooth.printNewLine();
    } else {
      throw Exception('Impresora no conectada');
    }
  }

  void _showBluetoothConnectionDialog() async {
    List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Seleccionar impresora'),
          content: SizedBox(
            width:
                MediaQuery.of(context).size.width * 0.8, // 80% of screen width
            height:
                MediaQuery.of(context).size.height *
                0.5, // 50% of screen height
            child: ListView.builder(
              shrinkWrap: true, // Importante para renderizar correctamente
              itemCount: devices.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(devices[index].name ?? ''),
                  subtitle: Text(devices[index].address ?? 'Sin dirección'),
                  onTap: () async {
                    try {
                      await bluetooth.connect(devices[index]);
                      setState(() {
                        _isPrinterConnected = true;
                      });
                      // ignore: use_build_context_synchronously
                      Navigator.of(context).pop();
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Impresora conectada')),
                      );
                    } catch (e) {
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al conectar: $e')),
                      );
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _location = '0';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _location = '0';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _location = '0';
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
        _location = '0';
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text('Error al tomar la foto: $e')));
    }
  }

  Future<void> _fetchZonas() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      print('══════════════════════════════════════════════════');
      print('🔵 Iniciando solicitud de zonas...');
      print('URL: ${Config.apiUrl}listarZonas');
      print(
        'Headers: ${{'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}}',
      );
      print(
        'Body: ${jsonEncode({'usuario': widget.usuario, 'db': widget.db})}',
      );

      final response = await http.post(
        Uri.parse('${Config.apiUrl}listarZonas'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'usuario': widget.usuario, 'db': widget.db}),
      );

      print('══════════════════════════════════════════════════');
      print('🟢 Respuesta recibida - Código: ${response.statusCode}');
      print('Headers de respuesta: ${response.headers}');

      // Imprimir el cuerpo de la respuesta formateado
      final responseBody = response.body;
      print('Body de respuesta (raw):');
      print(responseBody);

      try {
        final data = json.decode(responseBody);
        print('\nBody de respuesta (parsed JSON):');
        print('• Estado (e): ${data['e']}');

        if (data['data'] is List) {
          print('• Cantidad de zonas: ${data['data'].length}');
          print('\n📋 Lista completa de zonas:');

          for (var i = 0; i < data['data'].length; i++) {
            final zona = data['data'][i];
            print(
              '  ${i + 1}. Código: "${zona['codigo']}" | Nombre: "${zona['nombre']}"',
            );
          }
        } else {
          print('⚠️ El campo "data" no es una lista o no existe');
        }

        if (response.statusCode == 200) {
          if (data['e'] == 1 && data['data'] is List) {
            setState(() {
              zonas =
                  List<Map<String, dynamic>>.from(data['data'])
                      .where(
                        (zona) =>
                            zona['codigo'] != null && zona['nombre'] != null,
                      )
                      .toList();
            });
            print('\n🟢 Zonas cargadas correctamente en el estado');
          } else {
            print('\n🔴 Error en la estructura de la respuesta:');
            print(data);
          }
        }
      } catch (e) {
        print('\n🔴 Error al parsear JSON: $e');
      }

      print('══════════════════════════════════════════════════');
    } catch (e) {
      print('\n🔴 Error en la solicitud: $e');
      print('══════════════════════════════════════════════════');
    }
  }

  Future<void> _fetchAgencias(String zonaId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      print('══════════════════════════════════════════════════');
      print('🔵 Iniciando solicitud de agencias...');
      print('URL: ${Config.apiUrl}listarAgencias');

      // Crear el cuerpo de la solicitud según el formato requerido
      final requestBody = {
        "usuario": widget.usuario,
        "db": widget.db,
        "fecha": DateFormat(
          'yyyyMMdd',
        ).format(DateTime.now()), // Formato YYYYMMDD
        "tipo": "todas",
        "mostrar": "saldo",
        "zona": zonaId, // Usamos el código de zona recibido
        "banca": "0001",
      };

      print(
        'Headers: ${{'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}}',
      );
      print('Body: ${json.encode(requestBody)}');

      final response = await http.post(
        Uri.parse('${Config.apiUrl}listarAgencias'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody), // Enviamos el cuerpo completo
      );

      print('══════════════════════════════════════════════════');
      print('🟢 Respuesta recibida - Código: ${response.statusCode}');
      print('Headers de respuesta: ${response.headers}');

      final responseBody = response.body;
      print('Body de respuesta (raw):');
      print(responseBody);

      try {
        final data = json.decode(responseBody);
        print('\nBody de respuesta (parsed JSON):');
        print('• Estado (e): ${data['e']}');

        if (data['data'] is List) {
          print('• Cantidad de agencias: ${data['data'].length}');
          print('\n📋 Lista completa de agencias:');

          for (var i = 0; i < data['data'].length; i++) {
            final agencia = data['data'][i];
            print(
              '  ${i + 1}. Código: "${agencia['codigo']}" | Nombre: "${agencia['nombre']}" | Estado: ${agencia['estado']}',
            );
          }
        } else {
          print('⚠️ El campo "data" no es una lista o no existe');
        }

        if (response.statusCode == 200) {
          if (data['e'] == 1 && data['data'] is List) {
            setState(() {
              agencias =
                  List<Map<String, dynamic>>.from(data['data'])
                      .where(
                        (agencia) =>
                            agencia['codigo'] != null &&
                            agencia['nombre'] != null,
                      )
                      .toList();
            });
            print('\n🟢 Agencias cargadas correctamente en el estado');
          } else {
            print('\n🔴 Error en la estructura de la respuesta:');
            print(data);
          }
        }
      } catch (e) {
        print('\n🔴 Error al parsear JSON: $e');
      }

      print('══════════════════════════════════════════════════');
    } catch (e) {
      print('\n🔴 Error en la solicitud: $e');
      print('══════════════════════════════════════════════════');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar agencias: $e')));
    }
  }

  Future<void> _fetchSaldoAgencia(String codigoAgencia) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      setState(() {
        isLoadingSaldo = true;
      });

      final requestBody = {
        "usuario": widget.cobrador['id'].toString(),
        "db": widget.db,
        "fecha": DateFormat('yyyyMMdd').format(DateTime.now()),
        "tipo": "todas",
        "mostrar": "saldo",
        "agencia": codigoAgencia,
        "banca": "0001",
        "ubicacion": _location,
      };

      final response = await http
          .post(
            Uri.parse('${Config.apiUrl}detalleAgencia'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode(requestBody),
          )
          .timeout(Duration(seconds: 15));

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['e'] == 1) {
        if (data['data'] is List && data['data'].isNotEmpty) {
          final agenciaData = data['data'][0];
          setState(() {
            saldo = (agenciaData['acobrar']);
            nombreAgenciaSeleccionada = agenciaData['nombre']?.toString();
          });

          // Manejar los diferentes estados de ubicación
          final estadoUbicacion = data['ubicacion'] ?? 0;

          switch (estadoUbicacion) {
            case 0:
              _mostrarDialogoActualizarUbicacion(codigoAgencia);
              break;
            case 1:
              // Ubicación válida, continuar normalmente
              break;
            case 2:
              _mostrarDialogoUbicacionNoCoincide();
              break;
            default:
              break;
          }
        } else {
          throw Exception('No se encontraron datos de saldo para esta agencia');
        }
      } else {
        throw Exception(data['mensaje'] ?? 'Error al obtener el saldo');
      }
    } on TimeoutException {
      throw Exception('Tiempo de espera agotado al obtener saldo');
    } catch (e) {
      throw Exception('Error al obtener saldo: $e');
    } finally {
      setState(() {
        isLoadingSaldo = false;
      });
    }
  }

  Color _getSaldoColor(String? agenciaId) {
    if (agenciaId == null || saldo == null) return Colors.grey;

    // Buscar la agencia seleccionada
    final agencia = agencias.firstWhere(
      (agencia) => agencia['codigo']?.toString() == agenciaId,
      orElse: () => {'estado': null},
    );

    // Verificar el estado de la agencia
    final estado = agencia['estado'] as bool?;

    if (estado == true) {
      return Colors.green; // Estado true - verde (Cobrar)
    } else if (estado == false) {
      return Colors.red; // Estado false - rojo (Pagar)
    } else {
      return Colors.grey; // Estado desconocido - gris
    }
  }

  Future<void> _submitMonto() async {
    if (_montoController.text.isEmpty ||
        (double.tryParse(_montoController.text) ?? 0) == 0 &&
            (_fotoMontoCero == null || _explicacionController.text.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Datos requeridos incompletos')));
      return;
    }

    if (!_isPrinterConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Debe conectar una impresora antes de enviar')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.apiUrl}enviar'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      // Campos comunes
      request.fields.addAll({
        'idAgencia': selectedAgenciaId.toString(),
        'monto': _montoController.text,
        'device_id': _deviceId,
        'ubicacion': _location,
        'cobrador': widget.cobrador['id'].toString(),
        'fecha': _fechaController.text,
      });

      // Si el monto es cero, agregar la explicación
      if ((double.tryParse(_montoController.text) ?? 0) == 0) {
        request.fields['explicacion'] = _explicacionController.text;
      }

      // Agregar la imagen correspondiente
      File? imagenAEnviar =
          (double.tryParse(_montoController.text) ?? 0) == 0
              ? _fotoMontoCero
              : _selectedImage;

      if (imagenAEnviar != null) {
        var compressedImage = await _compressImage(imagenAEnviar);
        var imageStream = http.ByteStream(compressedImage!.openRead());
        var length = await compressedImage.length();

        request.files.add(
          http.MultipartFile(
            'imagen',
            imageStream,
            length,
            filename: 'comprobante.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      var response = await request.send().timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final data = json.decode(responseData);

        if (data['e'] == 1) {
          setState(() {
            _numeroTicket =
                data['ticket'].toString(); // Almacena el número de ticket
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Registro enviado exitosamente')),
          );

          setState(() {
            _selectedImage = null;
            _fotoMontoCero = null;
            _explicacionController.clear();
            _montoController.clear();
            _codigoController.clear();
            _mostrarFormularioMontoCero = false;
            _isMontoConfirmed = false;
            _isMontoCero = false;
          });

          if (await _checkPrinterConnection()) {
            await _printReceipt(data['mensaje']);
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<File?> _compressImage(File file) async {
    try {
      final dir = await Directory.systemTemp.createTemp();
      final targetPath = '${dir.path}/compressed.jpg';

      var result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 70, // Calidad de compresión (0-100)
        minWidth: 1024, // Ancho máximo
        minHeight: 1024, // Alto máximo
      );

      return result != null ? File(result.path) : null;
    } catch (e) {
      return null;
    }
  }

  void _mostrarDialogoActualizarUbicacion(String codigoAgencia) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10.0,
                  offset: Offset(0.0, 10.0),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gps_fixed, size: 50, color: Color(0xFF1A1B41)),
                SizedBox(height: 16),
                Text(
                  "Ubicación no registrada",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1B41),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  "Esta agencia no tiene ubicación registrada. ¿Desea actualizarla con su ubicación actual?",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Color(0xFF1A1B41), width: 1),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        "Cancelar",
                        style: TextStyle(
                          color: Color(0xFF1A1B41),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Color(0xFF1A1B41),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _actualizarUbicacionAgencia(codigoAgencia);
                      },
                      child: Text(
                        "Actualizar",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _actualizarUbicacionAgencia(String codigoAgencia) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      setState(() {
        _isSubmitting = true;
      });

      final requestBody = {
        "usuario": widget.usuario,
        "db": widget.db,
        "agencia": codigoAgencia,
        "ubicacion": _location,
        "banca": "0001",
      };

      final response = await http
          .post(
            Uri.parse('${Config.apiUrl}ubicacion'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode(requestBody),
          )
          .timeout(Duration(seconds: 15));

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['e'] == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ubicación actualizada correctamente')),
        );
      } else {
        throw Exception(data['mensaje'] ?? 'Error al actualizar la ubicación');
      }
    } on TimeoutException {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Tiempo de espera agotado')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar ubicación: $e')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _mostrarDialogoUbicacionNoCoincide() {
    showDialog(
      context: context,
      barrierDismissible: false, // El usuario debe tocar el botón para cerrar
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10.0,
                  offset: Offset(0.0, 10.0),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_rounded, size: 50, color: Colors.orange),
                SizedBox(height: 16),
                Text(
                  "Ubicación no coincide",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1B41),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  "No se encuentra dentro del rango permitido (20m) de la ubicación registrada de la agencia. Por favor, acérquese a la ubicación correcta.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                SizedBox(height: 24),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Color(0xFF1A1B41),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    "Entendido",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _mostrarModalMontoCero() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10.0,
                  offset: Offset(0.0, 10.0),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.money_off, size: 60, color: Colors.orange),
                  SizedBox(height: 16),
                  Text(
                    "Por favor, proporcione una foto y una descripción:",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                  SizedBox(height: 20),

                  // Foto
                  _fotoMontoCero != null
                      ? Column(
                        children: [
                          Container(
                            height: 150,
                            width: 150,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Image.file(
                              _fotoMontoCero!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          SizedBox(height: 10),
                          TextButton(
                            onPressed: _tomarFotoMontoCero,
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: Color(0xFF1A1B41), // Color azul oscuro
                                  width: 1,
                                ),
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            child: Text(
                              "Cambiar foto",
                              style: TextStyle(
                                color: Color(0xFF1A1B41), // Color azul oscuro
                              ),
                            ),
                          ),
                        ],
                      )
                      : ElevatedButton.icon(
                        onPressed: _tomarFotoMontoCero,
                        icon: Icon(Icons.camera_alt, color: Colors.white),
                        label: Text(
                          "Tomar foto",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(
                            0xFF6290C3,
                          ), // Color azul claro de tu tema
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),

                  SizedBox(height: 20),

                  // Campo de texto
                  TextField(
                    controller: _explicacionController,
                    maxLength: 160,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Descripción (requerido)",
                      border: OutlineInputBorder(),
                      hintText: "Describa por qué el monto es cero...",
                    ),
                  ),

                  SizedBox(height: 20),

                  // Botones
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: Color(0xFF1A1B41),
                              width: 1,
                            ),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _mostrarFormularioMontoCero = false;
                          });
                        },
                        child: Text(
                          "Cancelar",
                          style: TextStyle(
                            color: Color(0xFF1A1B41),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Color(0xFF1A1B41),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () {
                          if (_fotoMontoCero == null ||
                              _explicacionController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Foto y explicación son requeridas',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.of(context).pop();
                          _submitMonto();
                        },
                        child: Text(
                          "Confirmar",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _tomarFotoMontoCero() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _fotoMontoCero = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al tomar la foto: $e')));
    }
  }

  Future<void> _enviarCobroConNovedad() async {
    if (selectedAgenciaId == null || _montoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seleccione una agencia e ingrese un monto')),
      );
      return;
    }

    final monto = double.tryParse(_montoController.text) ?? 0;

    // Validación para montos distintos de cero
    if (monto != 0 && _codigoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ingrese el código de confirmación')),
      );
      return;
    }

    // Validación para monto cero
    if (monto == 0 &&
        (_fotoMontoCero == null || _explicacionController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Foto y explicación son requeridas para monto cero'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.apiUrl}insertarCobro'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      // Campos comunes
      request.fields.addAll({
        'usuario': widget.usuario,
        'db': widget.db,
        'agencia': selectedAgenciaId.toString(),
        'ubicacion': _location,
        'banca': '0001',
        'monto': _montoController.text,
        'proceso': 'enviado',
        'moneda': selectedMoneda ?? 'COP',
        'device': _deviceId,
        'fecha': _fechaController.text,
        'novedad': _novedadController.text,
        'codigo': monto != 0 ? _codigoController.text : '',
        'ticket': '',
      });

      // Adjuntar imagen solo para monto cero
      if (monto == 0 && _fotoMontoCero != null) {
        var compressedImage = await _compressImage(_fotoMontoCero!);
        var imageStream = http.ByteStream(compressedImage!.openRead());
        var length = await compressedImage.length();

        request.files.add(
          http.MultipartFile(
            'imagen',
            imageStream,
            length,
            filename: 'comprobante.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      var response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = json.decode(responseData);

      if (response.statusCode == 200 && data['e'] == 1) {
        setState(() {
          _numeroTicket = data['ticket'].toString();
        });

        _mostrarModalConfirmacion(data['data'], _numeroTicket ?? 'N/A');
        _resetFormulario();
      } else {
        throw Exception(data['mensaje'] ?? 'Error en el servidor');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar: $e')));
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _mostrarModalConfirmacion(String mensaje, String ticket) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Comprobante de Pago"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mensaje),
                SizedBox(height: 20),
                Text(
                  "Ticket N°: $ticket",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (_isPrinterConnected) {
                  _imprimirComprobante(mensaje, ticket);
                }
              },
              child: Text("CERRAR"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _imprimirComprobante(String mensaje, String ticket) async {
    try {
      BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

      if (await bluetooth.isConnected ?? false) {
        bluetooth.printNewLine();
        bluetooth.printCustom('COMPROBANTE DE COBRO', 2, 1);
        bluetooth.printNewLine();
        bluetooth.printCustom('---------------------', 1, 1);
        bluetooth.printCustom('Ticket: $ticket', 1, 0);
        bluetooth.printCustom('Fecha: ${_fechaController.text}', 1, 0);
        bluetooth.printCustom(
          'Agencia: ${nombreAgenciaSeleccionada ?? ''}',
          1,
          0,
        );
        bluetooth.printCustom(
          'Monto: ${_montoController.text} ${selectedMoneda ?? ''}',
          1,
          0,
        );
        bluetooth.printNewLine();
        bluetooth.printCustom(mensaje.split('-')[0], 1, 0);
        bluetooth.printNewLine();
        bluetooth.printCustom('Cobrador: ${widget.cobrador['nombre']}', 1, 0);
        bluetooth.printNewLine();
        bluetooth.printCustom('Gracias por su pago', 1, 1);
        bluetooth.printNewLine();
        bluetooth.printNewLine();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al imprimir: $e')));
    }
  }

  void _resetFormulario() {
    _montoController.clear();
    _codigoController.clear();
    _novedadController.clear();
    _explicacionController.clear();
    setState(() {
      _selectedImage = null;
      _fotoMontoCero = null;
      _isMontoConfirmed = false;
      _mostrarFormularioMontoCero = false;
      _isMontoCero = false;
    });
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'configurar_impresora':
        _showBluetoothConnectionDialog();
        break;
      case 'acerca_de':
        _mostrarAcercaDe();
        break;
    }
  }

  void _mostrarAcercaDe() {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10.0,
                    offset: Offset(0.0, 10.0),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo de la empresa
                  SizedBox(
                    height: 80,
                    child: Image.asset('assets/icon/logo.png'),
                  ),
                  SizedBox(height: 20),

                  // Nombre de la aplicación
                  Text(
                    'Sistema de Cobranza',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 10),

                  // Versión
                  Text(
                    'Versión 1.0.0',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 20),

                  // Línea divisoria
                  Divider(color: Colors.grey[300]),
                  SizedBox(height: 15),

                  // Créditos de desarrollo
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Desarrollado por:',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Sistemas y Asesorías MIT',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'SYAM',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),

                  // Botón de cierre - ESTA ES LA PARTE CORREGIDA
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Color(0xFF1A1B41),
                      padding: EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ), // Este paréntesis estaba faltando
                    ), // Cierre correcto de styleFrom
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cerrar',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Cambia el fondo a blanco

      appBar: AppBar(
        centerTitle: true, // Centra el título (y nuestro logo)
        title: Row(
          mainAxisSize:
              MainAxisSize.max, // Para que el Row no ocupe todo el ancho
          children: [
            Image.asset(
              'assets/icon/logo.png',
              height: 30, // Ajusta según necesites
              fit: BoxFit.contain,
            ),
            SizedBox(width: 15), // Espacio entre logo y texto
            Text(
              'Cobranza',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20, // Puedes ajustar el tamaño
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromARGB(168, 255, 174, 0), Color(0xFF1A1B41)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          // Botón de menú se mantiene igual
          PopupMenuButton<String>(
            surfaceTintColor: Colors.white,
            icon: Icon(Icons.more_vert, color: Colors.white),
            onSelected: (String result) {
              _handleMenuSelection(result);
            },
            itemBuilder:
                (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'configurar_impresora',
                    child: ListTile(
                      leading: Icon(Icons.print),
                      title: Text('Configurar impresora'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'acerca_de',
                    child: ListTile(
                      leading: Icon(Icons.info),
                      title: Text('Acerca de'),
                    ),
                  ),
                ],
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '${widget.cobrador['nombre']}'.toUpperCase(),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Card(
              color: Colors.white,
              elevation: 3, // Sombra más fuerte
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  16,
                ), // Bordes más redondeados
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          hint: Text("Selecciona una moneda"),
                          value: selectedMoneda,
                          isExpanded: true,
                          items:
                              widget.monedas.map<DropdownMenuItem<String>>((
                                moneda,
                              ) {
                                return DropdownMenuItem<String>(
                                  value: moneda,
                                  child: Text(
                                    moneda.toUpperCase(),
                                  ), // Mostrar la moneda en mayúsculas
                                );
                              }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              selectedMoneda = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 10), // Mayor espacio arriba
            // Zona Dropdown
            Card(
              color: Colors.white,
              elevation: 3, // Sombra más fuerte
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  16,
                ), // Bordes más redondeados
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          // Cambiado de DropdownButton<int> a DropdownButton<String>
                          hint: Text("Selecciona una zona"),
                          value:
                              selectedZonaId
                                  ?.toString(), // Asegúrate de que selectedZonaId sea String
                          isExpanded: true,
                          items:
                              zonas.map<DropdownMenuItem<String>>((zona) {
                                return DropdownMenuItem<String>(
                                  value: zona['codigo'].toString(),
                                  child: Text(zona['nombre'] ?? 'Sin nombre'),
                                );
                              }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                selectedZonaId =
                                    newValue; // Ahora manejamos el código como String
                                selectedAgenciaId = null;
                                saldo = null;
                                agencias = [];
                              });
                              // Necesitarás modificar _fetchAgencias para aceptar String
                              _fetchAgencias(newValue);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 10),

            // Agencia Dropdown
            Card(
              color: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dropdown de Agencias
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          hint: Text(
                            "Selecciona una agencia",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          value: selectedAgenciaId,
                          isExpanded: true,
                          items:
                              agencias.map<DropdownMenuItem<String>>((agencia) {
                                final isCobrar = agencia['estado'] == true;
                                final nombre =
                                    agencia['nombre']?.toString() ??
                                    'Sin nombre';
                                final codigo =
                                    agencia['codigo']?.toString() ?? '';

                                return DropdownMenuItem<String>(
                                  value: codigo,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isCobrar
                                            ? Icons.arrow_circle_up
                                            : Icons.arrow_circle_down,
                                        color:
                                            isCobrar
                                                ? Colors.green
                                                : Colors.red,
                                        size: 20,
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          nombre,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color:
                                                isCobrar
                                                    ? Colors.green
                                                    : Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                          onChanged: (String? newValue) async {
                            if (newValue == null) {
                              setState(() {
                                selectedAgenciaId = null;
                                saldo = null;
                                nombreAgenciaSeleccionada = null;
                              });
                              return;
                            }

                            try {
                              setState(() {
                                selectedAgenciaId = newValue;
                                saldo = null; // Resetear mientras se carga
                                isLoadingSaldo = true;
                              });

                              await _fetchSaldoAgencia(newValue);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error al cargar saldo: $e'),
                                ),
                              );
                            } finally {
                              setState(() {
                                isLoadingSaldo = false;
                              });
                            }
                          },
                        ),
                      ),
                    ),

                    // Mostrar saldo cuando esté disponible
                    if (selectedAgenciaId != null &&
                        nombreAgenciaSeleccionada != null)
                      if (selectedAgenciaId != null &&
                          nombreAgenciaSeleccionada != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Text(
                                  nombreAgenciaSeleccionada!,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(height: 10),
                              isLoadingSaldo
                                  ? CircularProgressIndicator()
                                  : Center(
                                    child: Text(
                                      saldo != null
                                          ? 'Saldo: $selectedMoneda ${saldo!}'
                                          : 'No se pudo obtener el saldo',
                                      style: TextStyle(
                                        fontSize: 26,
                                        color: _getSaldoColor(
                                          selectedAgenciaId,
                                        ),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Fecha
            TextField(
              controller: _fechaController,
              decoration: InputDecoration(
                labelText: 'Fecha de Cobro',
                labelStyle: TextStyle(
                  color: Colors.blueGrey, // Color del texto de la etiqueta
                  fontWeight:
                      FontWeight.w600, // Peso de fuente para mayor énfasis
                ),
                hintText:
                    'Selecciona una fecha', // Texto de sugerencia en el campo
                hintStyle: TextStyle(
                  color:
                      Colors
                          .grey[500], // Color gris para el texto de sugerencia
                ),
                prefixIcon: Icon(
                  Icons.calendar_today,
                  color: Colors.blue,
                ), // Ícono de calendario
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), // Bordes redondeados
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
                    width: 2,
                  ), // Color del borde
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
                    width: 2,
                  ), // Borde al recibir el foco
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.grey.shade200,
                    width: 2,
                  ), // Borde cuando está habilitado
                ),
                contentPadding: EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 16,
                ),
              ),
              readOnly: true,
              onTap: () => _selectDate(context),
            ),

            SizedBox(height: 20),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _montoController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    final monto = double.tryParse(value) ?? 0;
                    setState(() {
                      _isMontoCero = monto == 0 && value.isNotEmpty;
                      _mostrarFormularioMontoCero = _isMontoCero;
                    });

                    if (_isMontoCero) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _mostrarModalMontoCero();
                      });
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Monto recibido',
                    labelStyle: TextStyle(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.w600,
                    ),
                    hintText: 'Introduce el monto',
                    prefixIcon: Icon(
                      Icons.attach_money,
                      color: Colors.lightGreen,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.lightGreen,
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 16,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                CheckboxListTile(
                  checkColor: Colors.white,
                  activeColor: Color(0xFF6290C3),
                  title: Text("Confirmar monto"),
                  value: _isMontoConfirmed,
                  onChanged: (bool? value) {
                    setState(() {
                      _isMontoConfirmed = value ?? false;
                    });

                    if (_isMontoConfirmed && !_isMontoCero) {
                      _mostrarModal(
                        nombreAgenciaSeleccionada,
                        selectedZonaId.toString(),
                        _montoController.text,
                        _deviceId,
                        _fechaController.text,
                        "",
                      );
                    }
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                if (_isMontoConfirmed && !_isMontoCero) ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: _codigoController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Código de confirmación',
                      labelStyle: TextStyle(
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                      hintText: 'Introduce el código recibido',
                      prefixIcon: Icon(Icons.verified, color: Colors.blue),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blue, width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            SizedBox(height: 10),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceEvenly, // Espaciado uniforme entre los botones
              children: [
                // Enviar
                _isSubmitting
                    ? CircularProgressIndicator()
                    : ElevatedButton.icon(
                      onPressed:
                          (_isMontoConfirmed &&
                                  (_isMontoCero ||
                                      _codigoController.text.isNotEmpty))
                              ? _enviarCobroConNovedad
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (_isMontoConfirmed &&
                                    (_isMontoCero ||
                                        _codigoController.text.isNotEmpty))
                                ? Color(0xFF1A1B41)
                                : Colors.grey,
                        padding: EdgeInsets.symmetric(
                          horizontal: 80,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: Icon(Icons.send, color: Colors.white),
                      label: Text(
                        'Enviar',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
              ],
            ),
            SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _novedadController.dispose();
    _montoController.dispose();
    _fechaController.dispose();
    _explicacionController.dispose();
    _codigoController.dispose();
    super.dispose();
  }
}
