// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App Cobranza',
      theme: ThemeData(
        // Cambia el color primario y secundario
        colorScheme: ColorScheme.light(
          primary: Color(0xFF1A1B41), // Color principal
          secondary: Colors.grey[300]!, // Color secundario
          surface: Colors.white, // Color de fondo
        ),
        scaffoldBackgroundColor: Colors.white, // Fondo de las pantallas
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white, // Fondo del AppBar
          foregroundColor: Colors.black, // Color de íconos y texto
          elevation: 1, // Sombra sutil
        ),
        // Cambia el color de los diálogos
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        // Cambia el color del menú emergente
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        // Cambia el color del botón flotante
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        useMaterial3: true, // Si estás usando Material 3
      ),
      home: LoginScreen(),
    );
  }
}
