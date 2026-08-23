import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/navigation/home_navigation.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/env.dart' as env;
import 'package:surveygo/features/login/presentation/pages/login_page.dart';
import 'package:surveygo/features/settings/presentation/pages/qr_setup_page.dart';
import 'package:surveygo/features/splash/presentation/pages/splash_screen.dart';
import 'package:surveygo/core/utils/mbtiles_service.dart';
import 'package:surveygo/services/http_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MbtilesService().init();
  runApp(const MyApp());
}

Future<String> checkSession() async {
  final prefs = await SharedPreferences.getInstance();

  // Asegurar que siempre exista configuración precargando env.dart automáticamente
  if (!prefs.containsKey('config_ip') || (prefs.getString('config_ip') ?? '').isEmpty) {
    await prefs.setString('config_ip', env.ip);
    await prefs.setString('config_id_sistema', env.id_sistema.trim());
    await prefs.setString('config_id_cliente', env.id_cliente.trim());
  }

  // Flujo de sesión
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
