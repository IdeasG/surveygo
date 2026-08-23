import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/navigation/home_navigation.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/login/data/models/login_model.dart';
import 'package:surveygo/features/login/data/models/login_response.dart';
import 'package:surveygo/features/login/presentation/widgets/login_form.dart';
import 'package:surveygo/services/http_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final HttpProvider _httpProvider = HttpProvider();
  bool _isLoading = false;

  Future<void> _handleLogin(LoginModel loginModel, bool rememberMe) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _httpProvider.post('/movil/security/singin',
          body: loginModel.toJson());

      final loginResponse = LoginResponse.fromJson(response);

      if (loginResponse.isSuccess) {
        _httpProvider.updateHeaders({
          'Authorization': 'Bearer ${loginResponse.token}',
        });

        await _saveSession(
            loginResponse.token, loginModel.usuario, loginResponse.idUsuario);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loginResponse.message)),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeNavigation()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${loginResponse.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar con el servidor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _enterDemoMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', 'demo_token');
    await prefs.setString('username', 'Encuestador Demo');
    await prefs.setInt('userId', 1);
    await prefs.setBool('isLoggedIn', true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresando en Modo Demostración / Offline'),
          backgroundColor: AppColors.primaryColor,
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeNavigation()),
      );
    }
  }

  Future<void> _saveSession(String token, String username, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    await prefs.setInt('userId', userId);
    await prefs.setBool('isLoggedIn', true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    AppColors.secondaryColor,
                  ],
                  stops: [0.7, 1.0],
                ),
              ),
            ),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      height: 100,
                      width: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(15.0),
                        child: Image.asset('assets/icon/app_icon.png'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'SurveyGo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Plataforma de Encuestas Geoespaciales',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textColor,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: LoginForm(onSubmit: _handleLogin),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Botón para modo demostración / offline
                    OutlinedButton.icon(
                      icon: const Icon(Icons.rocket_launch, color: AppColors.primaryColor),
                      label: const Text(
                        'Acceso Rápido / Modo Demo Offline',
                        style: TextStyle(
                          color: AppColors.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.primaryColor, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _enterDemoMode,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: const Text('Reconfigurar Servidor (QR / IP)'),
                      onPressed: () => Navigator.pushNamed(context, '/qr-setup'),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
