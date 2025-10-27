import 'dart:io';
import 'dart:async';
import 'config.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'session_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '/screens/login_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import './screens/agencies_map_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http_parser/http_parser.dart';
import './services/pdf_generator_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final List<dynamic> moneda;
  final String usuario;
  final String db;
  final String? banca;

  const HomeScreen({
    super.key,
    required this.cobrador,
    required this.moneda,
    required this.usuario,
    required this.db,
    required this.banca,
  });

  @override
  // ignore: library_private_types_in_public_api
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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
  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _novedadController = TextEditingController();

  File? _fotoMontoCero;

  bool _tieneUltimoPago = false;
  bool isLoadingSaldo = false;
  bool _isSubmitting = false;
  bool _isMontoConfirmed = false; // Estado del checkbox
  bool _isPrinterConnected = false;
  bool _mostrarFormularioMontoCero = false;
  bool _isMontoCero = false;

  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  Map<String, dynamic>? _ultimoPago;
  Map<String, dynamic>? _ultimoTicketData;
  String? _ultimoTicketMensaje;
  String? _ultimoTicketNumero;
  String? _ultimoTicketRecibo;
  String? _ubicacionAgenciaActual;

  Timer? _inactivityTimer;
  Timer? _sessionCheckTimer;
  final Duration _sessionTimeout = Duration(minutes: 10);
  DateTime _lastInteractionTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    _initializeDeviceAndLocation();
    _checkBluetoothConnection();
    _setDefaultDate();
    _monedasList();

    // Inicializar el gestor de sesión y registrar interacción inicial
    SessionManager().initialize().then((_) {
      SessionManager().registerUserInteraction();
    });

    // Iniciar timers para verificación de inactividad
    _startInactivityTimer();
    _startSessionCheckTimer();

    // Cargar zonas después de un pequeño delay para asegurar que el contexto esté listo
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _fetchZonas();

        // Verificar si después de cargar las zonas no hay datos
        if (zonas.isEmpty) {
          // Esperar un poco más para asegurar que el diálogo se muestre correctamente
          await Future.delayed(Duration(milliseconds: 500));
          // El diálogo se mostrará automáticamente desde _fetchZonas si no hay rutas
        }
      } catch (e) {
        debugPrint('Error al cargar zonas en initState: $e');
      }
    });
  }

  @override
  void dispose() {
    // Cancelar timers y remover observer
    _inactivityTimer?.cancel();
    _sessionCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _novedadController.dispose();
    _montoController.dispose();
    _fechaController.dispose();
    _explicacionController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  // Cuando la app vuelve a primer plano, verificar si la sesión expiró
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionExpiry();
    }
  }

  // Iniciar timer de inactividad
  void _startInactivityTimer() {
    _inactivityTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      final now = DateTime.now();
      final difference = now.difference(_lastInteractionTime);

      if (difference > _sessionTimeout) {
        _logoutDueToInactivity();
      }
    });
  }

  // Iniciar timer para verificación periódica de sesión
  void _startSessionCheckTimer() {
    _sessionCheckTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _checkSessionExpiry();
    });
  }

  // Verificar si la sesión ha expirado
  Future<void> _checkSessionExpiry() async {
    if (SessionManager().isSessionExpired()) {
      _logoutDueToInactivity();
    } else {
      // Actualizar la interacción si la app está activa
      await SessionManager().registerUserInteraction();
    }
  }

  // Registrar interacción del usuario
  void _registerUserInteraction([_]) {
    _lastInteractionTime = DateTime.now();
    SessionManager().registerUserInteraction();
  }

  // Cerrar sesión por inactividad
  void _logoutDueToInactivity() {
    _inactivityTimer?.cancel();
    _sessionCheckTimer?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sesión Expirada'),
          content: Text(
            'Su sesión ha expirado por inactividad. Por favor, inicie sesión nuevamente.',
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Aceptar'),
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoUltimoPago(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarPorWhatsApp() async {
    try {
      if (_ultimoTicketData == null || _ultimoTicketNumero == null) {
        throw Exception('No hay información de ticket disponible');
      }

      setState(() {
        _isSubmitting = true;
      });

      // Generar PDF
      final pdfFile = await PdfGeneratorService.generarComprobantePDF(
        ticketNumero: _ultimoTicketNumero!,
        reciboNumero: _ultimoTicketRecibo ?? 'N/A',
        agencia: _ultimoTicketData!['agencia'] ?? 'N/A',
        zona: _ultimoTicketData!['zona'] ?? 'N/A',
        fecha: _ultimoTicketData!['fecha'] ?? 'N/A',
        monto: _ultimoTicketData!['monto'] ?? '0',
        moneda: _ultimoTicketData!['moneda'] ?? '',
        cobrador: widget.cobrador['nombre'],
        mensaje: _ultimoTicketMensaje ?? 'Transacción completada exitosamente',
      );

      // Mensaje corto para acompañar el archivo
      final mensajeCorto = '''
📋 COMPROBANTE DE COBRO

Ticket N°: ${_ultimoTicketNumero!}
Recibo N°: ${_ultimoTicketRecibo ?? 'N/A'}
Monto: ${_ultimoTicketData!['monto'] ?? '0'} ${_ultimoTicketData!['moneda'] ?? ''}

Sistema de Cobranza
${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}
''';

      // Compartir archivo PDF
      await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')],
        text: mensajeCorto,
        subject: 'Comprobante de Cobro ${_ultimoTicketNumero!}',
      );

      // Limpiar archivos temporales periódicamente
      await PdfGeneratorService.limpiarArchivosTemporales();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al generar/compartir comprobante: $e'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Error al generar PDF/WhatsApp: $e');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  // Cerrar sesión
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cobradorId');
    await prefs.remove('nombre');
    await prefs.remove('cedula');
    await prefs.remove('usuario');
    await prefs.remove('db');
    await prefs.remove('banca');

    await SessionManager().forceLogout();

    Navigator.pushReplacement(
      // ignore: use_build_context_synchronously
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  Future<void> _abrirGoogleMaps(String ubicacion) async {
    try {
      // 1. Validación básica
      if (ubicacion.isEmpty || ubicacion == '0') {
        throw Exception('Ubicación no válida');
      }

      // 2. Limpieza de coordenadas
      final coords =
          ubicacion
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      if (coords.length != 2) throw Exception('Formato debe ser "lat, lng"');

      // 3. Conversión a números
      final lat = double.tryParse(coords[0]);
      final lng = double.tryParse(coords[1]);

      if (lat == null || lng == null) {
        throw Exception('Coordenadas deben ser números');
      }

      // 4. Validación de rangos
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        throw Exception(
          'Coordenadas fuera de rango (lat: -90 a 90, lng: -180 a 180)',
        );
      }

      // 5. Construcción de URL
      final url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );

      // 6. Lanzamiento con fallback
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        // Fallback a versión web si falla la app
        await launchUrl(
          Uri.parse('https://www.google.com/maps?q=$lat,$lng'),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir el mapa: ${e.toString()}'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Error Google Maps: $e\nUbicación recibida: "$ubicacion"');
    }
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
    selectedMoneda = widget.moneda[0];
  }

  Color _getButtonColor() {
    if (!_isMontoConfirmed) return Colors.grey;

    final monto = double.tryParse(_montoController.text) ?? 0;
    final isMontoCero = monto == 0;

    if (isMontoCero) {
      return (_fotoMontoCero != null && _explicacionController.text.isNotEmpty)
          ? Color(0xFF1A1B41)
          : Colors.grey;
    } else {
      return Color(0xFF1A1B41);
    }
  }

  Future<bool> _mostrarDialogoImpresoraDesconectada() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              icon: Icon(
                Icons.warning_amber_rounded,
                size: 40,
                color: Colors.orange,
              ),
              title: Text(
                "Impresora Desconectada",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "La impresora no está conectada. ¿Desea enviar el comprobante por WhatsApp?",
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Puede configurar la impresora desde el menú de opciones.",
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false); // Cancelar
                  },
                  child: Text(
                    "Cancelar",
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true); // Continuar con WhatsApp
                  },
                  child: Text(
                    "Enviar por WhatsApp",
                    style: TextStyle(
                      color: Color(0xFF1A1B41),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _guardarUltimoTicket(String mensaje, String ticket, String recibo) {
    setState(() {
      _ultimoTicketData = {
        'agencia': nombreAgenciaSeleccionada,
        'zona': selectedZonaId,
        'monto': _montoController.text, // Asegurar que se guarda el monto
        'moneda': selectedMoneda,
        'fecha': _fechaController.text,
      };
      _ultimoTicketMensaje = mensaje;
      _ultimoTicketNumero = ticket;
      _ultimoTicketRecibo = recibo;
    });
  }

  void _mostrarModal(
    String? agencia,
    String zona,
    String monto,
    String deviceId,
    String fecha,
    String moneda,
  ) async {
    if ((double.tryParse(monto) ?? 0) == 0) {
      _mostrarModalMontoCero();
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final codigoConfirmacion = await _insertarCobro();

      if (codigoConfirmacion == null) {
        throw Exception('No se pudo obtener código de confirmación');
      } else {
        debugPrint('Código secreto: $codigoConfirmacion');
      }

      showDialog(
        // ignore: use_build_context_synchronously
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
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icono
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
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
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1B41),
                        ),
                      ),
                      SizedBox(height: 24),

                      // Info
                      _buildInfoRow("Agencia:", agencia ?? 'No especificada'),
                      _buildInfoRow("Zona:", zona),
                      SizedBox(height: 16),

                      // Monto
                      Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 24,
                        ),
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
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
                              "$monto $moneda",
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

                      TextField(
                        controller: _codigoController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Ingrese el código recibido',
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 6,
                      ),
                      SizedBox(height: 16),

                      // Campo novedad opcional
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
                      SizedBox(height: 24),

                      // Botones
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
                                if (_codigoController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Ingrese el código'),
                                    ),
                                  );
                                  return;
                                }

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
    } catch (e) {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
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

  Future<void> _fetchDeviceId() async {
    try {
      final uuid = await getOrCreateDeviceId();
      setState(() {
        _deviceId = uuid;
        debugPrint('UUID persistente: $_deviceId');
      });
    } catch (e) {
      setState(() {
        _deviceId = 'Error al obtener el ID';
      });
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

  Future<void> _fetchZonas() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      debugPrint('══════════════════════════════════════════════════');
      debugPrint('🔵 Iniciando solicitud de zonas...');
      debugPrint('URL: ${Config.apiUrl}listarZonas');

      // Crear el cuerpo de la petición con banca, banca puede ser null, revisar en API tal caso
      final requestBody = {
        'usuario': widget.usuario,
        'db': widget.db,
        'banca': widget.banca,
      };

      debugPrint(
        'Headers: ${{'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}}',
      );
      debugPrint('Body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse('${Config.apiUrl}listarZonas'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody), // Usar el requestBody que incluye banca
      );

      debugPrint('══════════════════════════════════════════════════');
      debugPrint('🟢 Respuesta recibida - Código: ${response.statusCode}');
      debugPrint('Headers de respuesta: ${response.headers}');

      // Imprimir el cuerpo de la respuesta formateado
      final responseBody = response.body;
      debugPrint('Body de respuesta (raw):');
      debugPrint(responseBody);

      try {
        final data = json.decode(responseBody);
        debugPrint('\nBody de respuesta (parsed JSON):');
        debugPrint('• Estado (e): ${data['e']}');

        // VALIDACIÓN CRÍTICA: Verificar si data es un Map vacío (no hay rutas)
        if (data['data'] is Map && (data['data'] as Map).isEmpty) {
          debugPrint('⚠️ No hay rutas cargadas para este usuario');

          // Mostrar diálogo informativo y hacer logout
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mostrarDialogoNoHayRutas();
          });
          return;
        }

        if (data['data'] is List) {
          debugPrint('• Cantidad de zonas: ${data['data'].length}');
          debugPrint('\n📋 Lista completa de zonas:');

          for (var i = 0; i < data['data'].length; i++) {
            final zona = data['data'][i];
            debugPrint(
              '  ${i + 1}. Código: "${zona['codigo']}" | Nombre: "${zona['nombre']}"',
            );
          }
        } else {
          debugPrint('⚠️ El campo "data" no es una lista o no existe');

          // Si data no es una lista y no es un Map vacío, también mostrar error
          if (data['data'] != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _mostrarDialogoNoHayRutas();
            });
            return;
          }
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
            debugPrint('\n🟢 Zonas cargadas correctamente en el estado');
          } else {
            debugPrint('\n🔴 Error en la estructura de la respuesta:');
            debugPrint(data.toString());

            // Si hay error en la estructura y no es un Map vacío, mostrar diálogo
            if (!(data['data'] is Map && (data['data'] as Map).isEmpty)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mostrarDialogoNoHayRutas();
              });
            }
          }
        }
      } catch (e) {
        debugPrint('\n🔴 Error al parsear JSON: $e');

        // En caso de error de parsing, también mostrar el diálogo
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mostrarDialogoNoHayRutas();
        });
      }

      debugPrint('══════════════════════════════════════════════════');
    } catch (e) {
      debugPrint('\n🔴 Error en la solicitud: $e');
      debugPrint('══════════════════════════════════════════════════');

      // En caso de error de red, también mostrar el diálogo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mostrarDialogoNoHayRutas();
      });
    }
  }

  // Método para mostrar el diálogo cuando no hay rutas
  void _mostrarDialogoNoHayRutas() {
    showDialog(
      context: context,
      barrierDismissible: false, // El usuario no puede cerrar tocando fuera
      builder: (BuildContext context) {
        return AlertDialog(
          icon: Icon(Icons.route_outlined, size: 40, color: Colors.orange),
          title: Text(
            "Sin Rutas Asignadas",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange[800],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "No hay rutas de cobranza cargadas para su usuario.",
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              SizedBox(height: 8),
              Text(
                "Por favor, contacte al administrador del sistema para que le asigne las rutas correspondientes.",
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _logout(); // Cerrar sesión automáticamente
              },
              child: Text(
                "Aceptar",
                style: TextStyle(
                  color: Color(0xFF1A1B41),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchAgencias(String zonaId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    String fechaParaConsulta;
    if (_fechaController.text.isNotEmpty) {
      fechaParaConsulta = _fechaController.text.replaceAll('-', '');
    } else {
      // Fallback a fecha actual si no hay fecha seleccionada
      fechaParaConsulta = DateFormat('yyyyMMdd').format(DateTime.now());
    }

    try {
      debugPrint('══════════════════════════════════════════════════');
      debugPrint('🔵 Iniciando solicitud de agencias...');
      debugPrint('URL: ${Config.apiUrl}listarAgencias');

      final requestBody = {
        "usuario": widget.usuario,
        "db": widget.db,
        "fecha": fechaParaConsulta, // Formato YYYYMMDD
        "tipo": "todas",
        "mostrar": "saldo",
        "zona": zonaId,
        "banca": widget.banca, // PUEDE SER NULL OJO no se valida en front
      };

      debugPrint(
        'Headers: ${{'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}}',
      );
      debugPrint('Body: ${json.encode(requestBody)}');

      final response = await http.post(
        Uri.parse('${Config.apiUrl}listarAgencias'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody), // Enviamos el cuerpo completo
      );

      debugPrint('══════════════════════════════════════════════════');
      debugPrint('🟢 Respuesta recibida - Código: ${response.statusCode}');
      debugPrint('Headers de respuesta: ${response.headers}');

      final responseBody = response.body;
      debugPrint('Body de respuesta (raw):');
      debugPrint(responseBody);

      try {
        final data = json.decode(responseBody);
        debugPrint('\nBody de respuesta (parsed JSON):');
        debugPrint('• Estado (e): ${data['e']}');

        // VALIDACIÓN CRÍTICA: Verificar si data es un Map vacío (no hay agencias en la zona)
        if (data['data'] is Map && (data['data'] as Map).isEmpty) {
          debugPrint('⚠️ No hay agencias cargadas para esta zona');

          // Mostrar diálogo informativo
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mostrarDialogoNoHayAgencias(zonaId);
          });

          setState(() {
            agencias = [];
          });
          return;
        }

        if (data['data'] is List) {
          debugPrint('• Cantidad de agencias: ${data['data'].length}');
          debugPrint('\n📋 Lista completa de agencias:');

          for (var i = 0; i < data['data'].length; i++) {
            final agencia = data['data'][i];
            debugPrint(
              '  ${i + 1}. Código: "${agencia['codigo']}" | Nombre: "${agencia['nombre']}" | Estado: ${agencia['estado']}',
            );
          }
        } else {
          debugPrint('⚠️ El campo "data" no es una lista o no existe');

          // Si data no es una lista y no es un Map vacío, también mostrar error
          if (data['data'] != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _mostrarDialogoNoHayAgencias(zonaId);
            });
          }

          setState(() {
            agencias = [];
          });
          return;
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
            debugPrint('\n🟢 Agencias cargadas correctamente en el estado');

            // Si la lista de agencias está vacía después del filtro, mostrar diálogo
            if (agencias.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mostrarDialogoNoHayAgencias(zonaId);
              });
            }
          } else {
            debugPrint('\n🔴 Error en la estructura de la respuesta:');
            debugPrint(data.toString());

            // Si hay error en la estructura y no es un Map vacío, mostrar diálogo
            if (!(data['data'] is Map && (data['data'] as Map).isEmpty)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mostrarDialogoNoHayAgencias(zonaId);
              });
            }

            setState(() {
              agencias = [];
            });
          }
        }
      } catch (e) {
        debugPrint('\n🔴 Error al parsear JSON: $e');

        // En caso de error de parsing, también mostrar el diálogo
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mostrarDialogoNoHayAgencias(zonaId);
        });

        setState(() {
          agencias = [];
        });
      }

      debugPrint('══════════════════════════════════════════════════');
    } catch (e) {
      debugPrint('\n🔴 Error en la solicitud: $e');
      debugPrint('══════════════════════════════════════════════════');

      // En caso de error de red, también mostrar el diálogo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mostrarDialogoNoHayAgencias(zonaId);
      });

      setState(() {
        agencias = [];
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar agencias: $e')));
    }
  }

  // Método para mostrar el diálogo cuando no hay agencias en la zona
  void _mostrarDialogoNoHayAgencias(String zonaId) {
    // Buscar el nombre de la zona seleccionada
    String nombreZona = 'la zona seleccionada';
    try {
      final zonaSeleccionada = zonas.firstWhere(
        (zona) => zona['codigo'].toString() == zonaId,
        orElse: () => {'nombre': 'Desconocida'},
      );
      nombreZona = '"${zonaSeleccionada['nombre']}"';
    } catch (e) {
      debugPrint('Error al obtener nombre de zona: $e');
    }

    showDialog(
      context: context,
      barrierDismissible: true, // El usuario puede cerrar tocando fuera
      builder: (BuildContext context) {
        return AlertDialog(
          icon: Icon(Icons.business_outlined, size: 40, color: Colors.blue),
          title: Text(
            "Sin Agencias Disponibles",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "No hay agencias disponibles para $nombreZona.",
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              SizedBox(height: 8),
              Text(
                "Puede seleccionar otra zona o contactar al administrador",
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                "Entendido",
                style: TextStyle(
                  color: Color(0xFF1A1B41),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchSaldoAgencia(String codigoAgencia) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      setState(() {
        isLoadingSaldo = true;
        _ultimoPago = null; // Resetear información de último pago
        _tieneUltimoPago = false;
      });

      // OBTENER LA FECHA DEL CONTROLADOR EN LUGAR DE LA FECHA ACTUAL
      String fechaParaConsulta;
      if (_fechaController.text.isNotEmpty) {
        fechaParaConsulta = _fechaController.text.replaceAll('-', '');
      } else {
        // Fallback a fecha actual si no hay fecha seleccionada
        fechaParaConsulta = DateFormat('yyyyMMdd').format(DateTime.now());
      }

      final requestBody = {
        "usuario": widget.cobrador['id'].toString(),
        "db": widget.db,
        "fecha": fechaParaConsulta, // USAR LA FECHA DEL CONTROLADOR
        "tipo": "todas",
        "mostrar": "saldo",
        "agencia": codigoAgencia,
        'banca': widget.banca,
        'ubicacion': _location,
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

          // CAPTURAR INFORMACIÓN DEL ÚLTIMO PAGO
          if (agenciaData['ult_pago'] is List &&
              agenciaData['ult_pago'].isNotEmpty) {
            final ultimoPagoData = agenciaData['ult_pago'][0];
            setState(() {
              _ultimoPago = {
                'fecha': ultimoPagoData['fecha']?.toString() ?? 'N/A',
                'monto': ultimoPagoData['monto']?.toString() ?? 'N/A',
                'cobrador': ultimoPagoData['cobrador']?.toString() ?? 'N/A',
                'hace': ultimoPagoData['hace']?.toString() ?? 'N/A',
              };
              _tieneUltimoPago = true;
            });
            debugPrint('📋 Último pago encontrado: $_ultimoPago');
          } else {
            setState(() {
              _ultimoPago = null;
              _tieneUltimoPago = false;
            });
          }

          setState(() {
            saldo = (agenciaData['acobrar']);
            nombreAgenciaSeleccionada = agenciaData['nombre']?.toString();
            _ubicacionAgenciaActual = agenciaData['ubicacion']?.toString();
            debugPrint(
              'Ubicación agencia ${agenciaData['codigo']}: $_ubicacionAgenciaActual',
            );

            // Guardar siempre la ubicación si existe
            if (agenciaData['ubicacion'] != null) {
              _ultimoTicketData ??= {};
              _ultimoTicketData!['ubicacionAgencia'] =
                  agenciaData['ubicacion'].toString();
            }
          });

          // Manejar los diferentes estados de ubicación
          final estadoUbicacion = data['ubicacion'] ?? 0;
          final ubicacionAgencia = agenciaData['ubicacion']?.toString() ?? '0';

          // Mostrar diálogo si:
          // 1. El estado de ubicación es 0 (no registrada)
          // 2. O si la ubicación actual es "0" (string)
          if (estadoUbicacion == 0 || ubicacionAgencia == '0') {
            _mostrarDialogoActualizarUbicacion(codigoAgencia);
          } else if (estadoUbicacion == 2) {
            // Mostrar advertencia si la ubicación no coincide
            _mostrarDialogoUbicacionNoCoincide();
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

  String _formatearMonto(String monto) {
    try {
      final montoNum = double.tryParse(monto);
      if (montoNum == null) return monto;

      final formatter = NumberFormat.currency(
        symbol: '\$',
        decimalDigits: 2,
        locale: 'es_CO',
      );
      return formatter.format(montoNum);
    } catch (e) {
      return monto;
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
        "banca": widget.banca,
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
        setState(() {
          _ubicacionAgenciaActual = _location;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ubicación actualizada correctamente')),
        );
        await _fetchSaldoAgencia(codigoAgencia);
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

  Future<void> _procesarMontoCero() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      // 1. Primero insertar el cobro
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final insertResponse = await http.post(
        Uri.parse('${Config.apiUrl}insertarCobro'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'usuario': widget.usuario,
          'db': widget.db,
          'agencia': selectedAgenciaId.toString(),
          'ubicacion': _location,
          'banca': widget.banca,
          'monto': '0',
          'proceso': 'enviado',
          'moneda': selectedMoneda ?? 'COP',
          'device': _deviceId,
          'fecha': _fechaController.text,
          'novedad': _explicacionController.text,
        }),
      );

      final insertData = json.decode(insertResponse.body);
      if (insertResponse.statusCode != 200 || insertData['e'] != 1) {
        throw Exception(insertData['mensaje'] ?? 'Error al insertar cobro');
      }

      // Extraer el código de confirmación del mensaje
      final mensaje = insertData['data'] as String;
      final regex = RegExp(r'código: (\d+)');
      final match = regex.firstMatch(mensaje);
      final codigoConfirmacion = match?.group(1) ?? '';

      if (codigoConfirmacion.isEmpty) {
        throw Exception('No se pudo obtener código de confirmación');
      }

      // 2. Enviar directamente con la foto y el código obtenido
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.apiUrl}enviar'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll({
        'usuario': widget.usuario,
        'db': widget.db,
        'agencia': selectedAgenciaId.toString(),
        'ubicacion': _location,
        'banca': widget.banca!,
        'monto': '0',
        'codigo': codigoConfirmacion,
        'novedad': _explicacionController.text,
        'ticket': insertData['ticket']?.toString() ?? '',
      });

      // Adjuntar la foto comprimida
      var compressedImage = await _compressImage(_fotoMontoCero!);
      var imageStream = http.ByteStream(compressedImage!.openRead());
      var length = await compressedImage.length();

      request.files.add(
        http.MultipartFile(
          'imagen',
          imageStream,
          length,
          filename: 'comprobante_monto_cero.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      var sendResponse = await request.send();
      final sendData = json.decode(await sendResponse.stream.bytesToString());

      if (sendResponse.statusCode == 200 && sendData['e'] == 1) {
        _mostrarModalConfirmacion(
          sendData['mensaje'],
          sendData['ticket']?.toString() ?? 'N/A',
          sendData['recibo']?.toString() ?? 'N/A',
        );

        // Imprimir automáticamente si la impresora está conectada
        if (_isPrinterConnected) {
          await _imprimirComprobante(
            sendData['mensaje'],
            sendData['ticket']?.toString() ?? 'N/A',
            sendData['recibo']?.toString() ?? '',
            _montoController.text,
          );
        }

        _resetFormulario();
      } else {
        throw Exception(sendData['mensaje'] ?? 'Error al enviar monto cero');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error en monto cero: $e')));
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
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
          elevation: 8,
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Registro de Monto Cero",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1B41),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  "Para registrar un monto cero, es requerido adjuntar una foto y una explicación.",
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),

                // Campo para la foto
                if (_fotoMontoCero == null)
                  ElevatedButton(
                    onPressed: _tomarFotoMontoCero,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF1A1B41),
                    ),
                    child: Text(
                      "Tomar Foto",
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                else
                  Column(
                    children: [
                      Image.file(
                        _fotoMontoCero!,
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                      TextButton(
                        onPressed: _tomarFotoMontoCero,
                        child: Text("Cambiar Foto"),
                      ),
                    ],
                  ),

                SizedBox(height: 20),

                // Campo para la explicación
                TextField(
                  controller: _explicacionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Explicación*",
                    hintText: "Explique por qué el monto es cero",
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 24),

                // Botones
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _mostrarFormularioMontoCero = false;
                          _montoController.clear();
                        });
                      },
                      child: Text("Cancelar"),
                    ),
                    ElevatedButton(
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
                        _procesarMontoCero();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1A1B41),
                      ),
                      child: Text(
                        "Confirmar",
                        style: TextStyle(color: Colors.white),
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

  Future<String?> _insertarCobro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.post(
        Uri.parse('${Config.apiUrl}insertarCobro'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'usuario': widget.usuario,
          'db': widget.db,
          'agencia': selectedAgenciaId.toString(),
          'ubicacion': _location,
          'banca': widget.banca,
          'monto': _montoController.text,
          'proceso': 'enviado',
          'moneda': selectedMoneda ?? 'COP',
          'device': _deviceId,
          'fecha': _fechaController.text,
          'novedad': _novedadController.text,
        }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['e'] == 1) {
        // Extraer el código de confirmación del mensaje
        final mensaje = data['data'] as String;
        final regex = RegExp(r'código: (\d+)');
        final match = regex.firstMatch(mensaje);

        if (match != null) {
          setState(() {
            _numeroTicket = data['ticket']?.toString();
          });
          return match.group(1); // Retorna el código numérico
        }
        throw Exception('No se pudo extraer código de confirmación');
      } else {
        throw Exception(data['mensaje'] ?? 'Error al insertar cobro');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al insertar cobro: $e')));
      return null;
    }
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

      // Campos comunes para todos los montos
      request.fields.addAll({
        'usuario': widget.usuario,
        'db': widget.db,
        'agencia': selectedAgenciaId.toString(),
        'ubicacion': _location,
        'banca': widget.banca!,
        'monto': _montoController.text,
        'codigo': _codigoController.text,
        'novedad': _novedadController.text,
        'ticket': _numeroTicket ?? '',
      });

      // Solo adjuntar imagen para monto cero
      if ((double.tryParse(_montoController.text) ?? 0) == 0 &&
          _fotoMontoCero != null) {
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
        // Mostrar confirmación con ambas opciones
        _mostrarModalConfirmacion(
          data['mensaje'],
          data['ticket']?.toString() ?? 'N/A',
          data['recibo']?.toString() ?? 'N/A',
        );

        // Imprimir automáticamente si la impresora está conectada
        if (_isPrinterConnected) {
          await _imprimirComprobante(
            data['mensaje'],
            data['ticket']?.toString() ?? 'N/A',
            data['recibo']?.toString() ?? '',
            _montoController.text,
          );
        }

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

  void _mostrarModalConfirmacion(String mensaje, String ticket, String recibo) {
    _guardarUltimoTicket(mensaje, ticket, recibo);

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
                SizedBox(height: 10),
                Text(
                  "Recibo N°: $recibo",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Botón de WhatsApp - SIEMPRE DISPONIBLE
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: _enviarPorWhatsApp,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send, color: Colors.white),
                  SizedBox(width: 8),
                  Text("WhatsApp", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            // Botón de imprimir - SIEMPRE VISIBLE, pero deshabilitado si no hay conexión
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isPrinterConnected ? Color(0xFF1A1B41) : Colors.grey,
                foregroundColor: Colors.white,
              ),
              onPressed:
                  _isPrinterConnected
                      ? () async {
                        await _imprimirComprobante(
                          mensaje,
                          ticket,
                          recibo,
                          _montoController.text,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ticket impreso correctamente'),
                          ),
                        );
                      }
                      : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.print, color: Colors.white),
                  SizedBox(width: 8),
                  Text("Imprimir", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("CERRAR"),
            ),
          ],
        );
      },
    );
  }

  void _mostrarUltimoTicket() {
    if (_ultimoTicketData == null ||
        _ultimoTicketMensaje == null ||
        _ultimoTicketNumero == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No hay información de último ticket disponible'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Center(child: Text("Último Ticket")),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_ultimoTicketMensaje!),
                SizedBox(height: 10),
                Text(
                  "Agencia: ${_ultimoTicketData!['agencia'] ?? 'N/A'}",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Zona: ${_ultimoTicketData!['zona'] ?? 'N/A'}",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Fecha: ${_ultimoTicketData!['fecha'] ?? 'N/A'}",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                Text(
                  "Monto: ${_ultimoTicketData!['monto'] ?? '0'} ${_ultimoTicketData!['moneda'] ?? ''}",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                SizedBox(height: 20),
                Text(
                  "Ticket N°: $_ultimoTicketNumero",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.blue,
                  ),
                ),
                if (_ultimoTicketRecibo != null) ...[
                  SizedBox(height: 10),
                  Text(
                    "Recibo N°: $_ultimoTicketRecibo",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green,
                    ),
                  ),
                ],
                // Mostrar estado de la impresora
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isPrinterConnected ? Icons.check_circle : Icons.error,
                        color:
                            _isPrinterConnected ? Colors.green : Colors.orange,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        _isPrinterConnected
                            ? 'Impresora conectada'
                            : 'Impresora desconectada',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              _isPrinterConnected
                                  ? Colors.green
                                  : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Botón de WhatsApp - SIEMPRE DISPONIBLE
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: _enviarPorWhatsApp,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send, color: Colors.white),
                  SizedBox(width: 8),
                  Text("WhatsApp", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            // Botón de imprimir - SIEMPRE VISIBLE, pero deshabilitado si no hay conexión
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isPrinterConnected ? Color(0xFF1A1B41) : Colors.grey,
                foregroundColor: Colors.white,
              ),
              onPressed:
                  _isPrinterConnected
                      ? () async {
                        await _imprimirComprobante(
                          _ultimoTicketMensaje!,
                          _ultimoTicketNumero!,
                          _ultimoTicketRecibo ?? '',
                          _ultimoTicketData!['monto'] ?? '0',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ticket reimpreso correctamente'),
                          ),
                        );
                      }
                      : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.print, color: Colors.white),
                  SizedBox(width: 8),
                  Text("Reimprimir", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Cerrar"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _imprimirComprobante(
    String mensaje,
    String ticket,
    String recibo,
    String monto,
  ) async {
    try {
      BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

      if (await bluetooth.isConnected ?? false) {
        // Configuración inicial
        bluetooth.printNewLine();

        // Intentar imprimir el logo
        try {
          // Cargar la imagen como bytes
          final ByteData byteData = await rootBundle.load(
            'assets/icon/impresora.png',
          );
          final Uint8List imageBytes = byteData.buffer.asUint8List();

          // Para impresoras térmicas, usar printImageBytes es más confiable
          bluetooth.printImageBytes(imageBytes);
          bluetooth.printNewLine();
          bluetooth.printNewLine();
        } catch (e) {
          debugPrint('Error al imprimir logo: $e');
          // Encabezado alternativo si falla la imagen
          bluetooth.printCustom('*** COMPROBANTE DE COBRO ***', 1, 1);
          bluetooth.printNewLine();
        }

        // Contenido del comprobante
        bluetooth.printCustom('COMPROBANTE DE COBRO', 1, 1);
        bluetooth.printNewLine();
        bluetooth.printCustom('-----------------------------', 1, 1);
        bluetooth.printCustom('Recibo: $recibo', 1, 0);
        bluetooth.printCustom('Ticket: $ticket', 1, 0);
        bluetooth.printCustom('Fecha: ${_fechaController.text}', 1, 0);
        bluetooth.printCustom(
          'Agencia: ${nombreAgenciaSeleccionada ?? ''}',
          1,
          0,
        );
        bluetooth.printCustom('Monto: $monto ${selectedMoneda ?? ''}', 1, 0);
        bluetooth.printNewLine();

        // Mensaje principal
        List<String> mensajeLines = _splitText(
          mensaje,
          32,
        ); // 32 caracteres por línea
        for (String line in mensajeLines) {
          bluetooth.printCustom(line, 1, 0);
        }

        bluetooth.printNewLine();
        bluetooth.printCustom('Cobrador: ${widget.cobrador['nombre']}', 1, 0);
        bluetooth.printNewLine();
        bluetooth.printCustom('-- Gracias por su pago --', 1, 1);
        bluetooth.printNewLine();
        bluetooth.printNewLine();
        bluetooth.printNewLine();

        // Cortar papel (si la impresora lo soporta)
        bluetooth.paperCut();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Impresora no conectada')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al imprimir: $e')));
      debugPrint('Error detallado en impresión: $e');
    }
  }

  // Método auxiliar para dividir texto en líneas
  List<String> _splitText(String text, int maxLength) {
    List<String> lines = [];
    String remainingText = text;

    while (remainingText.length > maxLength) {
      int breakPoint = remainingText.lastIndexOf(' ', maxLength);
      if (breakPoint == -1) breakPoint = maxLength;

      lines.add(remainingText.substring(0, breakPoint));
      remainingText = remainingText.substring(breakPoint).trim();
    }

    if (remainingText.isNotEmpty) {
      lines.add(remainingText);
    }

    return lines;
  }

  // En el método _resetFormulario:
  void _resetFormulario() {
    _montoController.clear();
    _codigoController.clear();
    _novedadController.clear();
    _explicacionController.clear();
    setState(() {
      // _selectedImage = null;
      _fotoMontoCero = null;
      _isMontoConfirmed = false;
      _mostrarFormularioMontoCero = false;
      _isMontoCero = false;
      _numeroTicket = null;
    });
  }

  String _getRemainingTimeString() {
    final remainingSeconds = SessionManager().getRemainingTime();
    if (remainingSeconds <= 0) return '00:00';

    final minutes = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _handleMenuSelection(String value) async {
    switch (value) {
      case 'configurar_impresora':
        _showBluetoothConnectionDialog();
        break;
      case 'acerca_de':
        _mostrarAcercaDe();
        break;
      case 'ultimo_ticket':
        _mostrarUltimoTicket();
        break;
      case 'ver_mapa':
        if (selectedZonaId == null || agencias.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Seleccione una zona con agencias primero'),
            ),
          );
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AgenciesMapScreen(agencies: agencias),
          ),
        );
        break;
      case 'cerrar_sesion':
        _logout();
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
    if (_isMontoConfirmed && _isMontoCero && !_mostrarFormularioMontoCero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mostrarModalMontoCero();
      });
    }

    return Listener(
      onPointerDown: _registerUserInteraction,
      onPointerMove: _registerUserInteraction,
      onPointerUp: _registerUserInteraction,
      child: GestureDetector(
        onTap: _registerUserInteraction,
        onPanDown: _registerUserInteraction,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            centerTitle: true,
            title: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Image.asset(
                  'assets/icon/logo.png',
                  height: 30,
                  fit: BoxFit.contain,
                ),
                SizedBox(width: 15),
                Text(
                  'Cobranza',
                  style: TextStyle(color: Colors.white, fontSize: 20),
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
              // Indicador de estado de impresora
              Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isPrinterConnected ? Icons.print : Icons.print_disabled,
                      color: _isPrinterConnected ? Colors.white : Colors.yellow,
                      size: 18,
                    ),
                    Text(
                      _isPrinterConnected ? 'Conectada' : 'Desconectada',
                      style: TextStyle(fontSize: 8, color: Colors.white),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                surfaceTintColor: Colors.white,
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: _handleMenuSelection,

                itemBuilder:
                    (BuildContext context) => [
                      const PopupMenuItem<String>(
                        value: 'configurar_impresora',
                        child: ListTile(
                          leading: Icon(Icons.print),
                          title: Text('Configurar impresora'),
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'ultimo_ticket',
                        child: ListTile(
                          leading: Icon(Icons.receipt),
                          title: Text('Último ticket'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'ver_mapa',
                        enabled: selectedZonaId != null && agencias.isNotEmpty,
                        child: const ListTile(
                          leading: Icon(Icons.map),
                          title: Text('Ver mapa de agencias'),
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'acerca_de',
                        child: ListTile(
                          leading: Icon(Icons.info),
                          title: Text('Acerca de'),
                        ),
                      ),

                      PopupMenuItem<String>(
                        value: 'cerrar_sesion',
                        child: const ListTile(
                          leading: Icon(Icons.logout, color: Colors.red),
                          title: Text(
                            'Cerrar sesión',
                            style: TextStyle(color: Colors.red),
                          ),
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
                                  widget.moneda.map<DropdownMenuItem<String>>((
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

                SizedBox(height: 20),

                TextField(
                  controller: _fechaController,
                  decoration: InputDecoration(
                    labelText: 'Fecha de Corte',
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
                      borderRadius: BorderRadius.circular(
                        10,
                      ), // Bordes redondeados
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
                                      child: Text(
                                        // ignore: prefer_interpolation_to_compose_strings
                                        '${zona['codigo']} - ' + zona['nombre'],
                                      ),
                                    );
                                  }).toList(),

                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    selectedZonaId = newValue;
                                    selectedAgenciaId = null;
                                    saldo = null;
                                    agencias =
                                        []; // Limpiar agencias inmediatamente
                                    nombreAgenciaSeleccionada = null;
                                  });
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
                                  agencias.map<DropdownMenuItem<String>>((
                                    agencia,
                                  ) {
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
                                              '$codigo | $nombre',
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
                                    _ultimoPago = null; // Resetear último pago
                                    _tieneUltimoPago = false;
                                  });

                                  await _fetchSaldoAgencia(newValue);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error al cargar saldo: $e',
                                      ),
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
                                    : Column(
                                      children: [
                                        Center(
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
                                        SizedBox(height: 10),

                                        // Botón de Google Maps - Versión definitiva
                                        Visibility(
                                          visible:
                                              _ubicacionAgenciaActual !=
                                              null, // Siempre visible si hay dato
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8.0,
                                            ),
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                if (_ubicacionAgenciaActual ==
                                                        null ||
                                                    _ubicacionAgenciaActual ==
                                                        '0') {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Esta agencia no tiene ubicación registrada',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      backgroundColor:
                                                          Colors.orange,
                                                    ),
                                                  );
                                                } else {
                                                  _abrirGoogleMaps(
                                                    _ubicacionAgenciaActual!,
                                                  );
                                                }
                                              },
                                              icon: Icon(
                                                _ubicacionAgenciaActual ==
                                                            null ||
                                                        _ubicacionAgenciaActual ==
                                                            '0'
                                                    ? Icons.location_off
                                                    : Icons.map,
                                                size: 20,
                                              ),
                                              label: Text(
                                                _ubicacionAgenciaActual ==
                                                            null ||
                                                        _ubicacionAgenciaActual ==
                                                            '0'
                                                    ? 'Sin ubicación registrada'
                                                    : 'Ver en Google Maps',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    _ubicacionAgenciaActual ==
                                                                null ||
                                                            _ubicacionAgenciaActual ==
                                                                '0'
                                                        ? Colors.grey[600]
                                                        : Color(0xFF1A1B41),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  // padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                        if (_tieneUltimoPago &&
                                            _ultimoPago != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 16.0,
                                            ),
                                            child: Container(
                                              padding: EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.blue[50],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.blue[200]!,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '📋 Último Pago Registrado', //revisar en backend la fecha enviada para el ultimo pago
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.blue[800],
                                                    ),
                                                  ),
                                                  SizedBox(height: 8),
                                                  _buildInfoUltimoPago(
                                                    'Fecha de corte:',
                                                    _ultimoPago!['fecha'], //llega de la api el dia q realizo el cobro NO la fecha de corte de ese cobro
                                                  ),
                                                  _buildInfoUltimoPago(
                                                    'Monto:',
                                                    _formatearMonto(
                                                      _ultimoPago!['monto'],
                                                    ),
                                                  ),
                                                  _buildInfoUltimoPago(
                                                    'Cobrador:',
                                                    _ultimoPago!['cobrador'],
                                                  ),
                                                  if (_ultimoPago!['hace'] !=
                                                          'N/A' &&
                                                      _ultimoPago!['hace'] !=
                                                          '0')
                                                    _buildInfoUltimoPago(
                                                      'Hace:',
                                                      '${_ultimoPago!['hace']} días',
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 20),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _montoController,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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

                        // Mostrar modal tanto para montos cero como no cero
                        if (_isMontoConfirmed) {
                          if (_isMontoCero) {
                            _mostrarModalMontoCero();
                          } else {
                            _mostrarModal(
                              nombreAgenciaSeleccionada,
                              selectedZonaId.toString(),
                              _montoController.text,
                              _deviceId,
                              _fechaController.text,
                              "",
                            );
                          }
                        }
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),

                SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _isSubmitting
                        ? CircularProgressIndicator()
                        : ElevatedButton.icon(
                          onPressed: () {
                            final monto =
                                double.tryParse(_montoController.text) ?? 0;
                            final isMontoCero = monto == 0;

                            if (isMontoCero) {
                              if (_fotoMontoCero != null &&
                                  _explicacionController.text.isNotEmpty) {
                                _enviarCobroConNovedad();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Para monto cero, se requieren foto y explicación',
                                    ),
                                  ),
                                );
                              }
                            } else {
                              if (_isMontoConfirmed) {
                                _enviarCobroConNovedad();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Por favor confirme el monto primero',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _getButtonColor(),
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

                SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Text(
                    'Sesión activa - Tiempo restante: ${_getRemainingTimeString()}',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
