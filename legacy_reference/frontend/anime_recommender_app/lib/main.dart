import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/login_screen.dart';

void main() {
  // Asegura que los WidgetsBinding estén inicializados antes de usar servicios.
  WidgetsFlutterBinding.ensureInitialized();
  
  // Bloquear rotación - solo vertical
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime Recommender',
      
      // ✅ CORRECCIÓN DEL ERROR DE THEMEDATA
      // Se reemplaza 'primarySwatch' por 'colorScheme' y se añade 'useMaterial3'.
      theme: ThemeData(
        // Genera un ColorScheme a partir de un color principal.
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blue,
          brightness: Brightness.light, // Necesario para evitar la falla de aserción
        ),
        // Habilitar Material 3 (opcional, pero recomendado)
        useMaterial3: true, 
      ),
      
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}