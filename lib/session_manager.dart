import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  static const String _lastInteractionKey = 'last_interaction';
  static const int _sessionTimeout =
      10 * 60 * 1000; // 10 minutos en milisegundos

  DateTime? _lastInteraction;
  bool _isSessionExpired = false;

  // Inicializar el gestor de sesión
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final lastInteractionMillis = prefs.getInt(_lastInteractionKey);

    if (lastInteractionMillis != null) {
      _lastInteraction = DateTime.fromMillisecondsSinceEpoch(
        lastInteractionMillis,
      );

      // Verificar si la sesión ya expiró al iniciar
      if (DateTime.now().difference(_lastInteraction!).inMilliseconds >
          _sessionTimeout) {
        _isSessionExpired = true;
      }
    }
  }

  // Registrar interacción del usuario
  Future<void> registerUserInteraction() async {
    _lastInteraction = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastInteractionKey,
      _lastInteraction!.millisecondsSinceEpoch,
    );
    _isSessionExpired = false;
  }

  // Verificar si la sesión ha expirado
  bool isSessionExpired() {
    if (_lastInteraction == null) return true;

    final now = DateTime.now();
    final difference = now.difference(_lastInteraction!).inMilliseconds;

    return difference > _sessionTimeout || _isSessionExpired;
  }

  // Forzar cierre de sesión
  Future<void> forceLogout() async {
    _isSessionExpired = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastInteractionKey);
  }

  // Obtener tiempo restante de sesión
  int getRemainingTime() {
    if (_lastInteraction == null) return 0;

    final now = DateTime.now();
    final difference = now.difference(_lastInteraction!).inMilliseconds;
    final remaining = _sessionTimeout - difference;

    return remaining > 0 ? remaining ~/ 1000 : 0; // Devuelve segundos restantes
  }
}
