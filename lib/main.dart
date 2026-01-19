import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/navigation/home_navigation.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/login/presentation/pages/login_page.dart';
import 'package:surveygo/features/settings/presentation/pages/qr_setup_page.dart';
import 'package:surveygo/features/splash/presentation/pages/splash_screen.dart';
import 'package:surveygo/services/http_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

Future<String> checkSession() async {
  final prefs = await SharedPreferences.getInstance();

  // Primero verificar si existe configuración del QR
  final ip = prefs.getString('config_ip') ?? '';
  final idSistema = prefs.getString('config_id_sistema') ?? '';
  final idCliente = prefs.getString('config_id_cliente') ?? '';
  final hasConfig =
      ip.isNotEmpty && idSistema.isNotEmpty && idCliente.isNotEmpty;
  if (!hasConfig) {
    return '/qr-setup';
  }

  // Luego flujo de sesión
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  if (isLoggedIn) {
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) {
      final httpProvider = HttpProvider();
      httpProvider.updateHeaders({
        'Authorization': 'Bearer $token',
      });
      return '/home';
    }
  }
  return '/login';
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SurveyGo',
      theme: ThemeData(
        primaryColor: AppColors.primaryColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryColor,
          secondary: AppColors.secondaryColor,
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomeNavigation(),
        '/qr-setup': (context) => const QrSetupPage(),
      },
    );
  }
}
