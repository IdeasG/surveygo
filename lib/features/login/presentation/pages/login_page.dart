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
      // Llamada real al API usando HttpProvider
      final response = await _httpProvider.post('/movil/security/singin',
          body: loginModel.toJson());

      // Procesar la respuesta
      final loginResponse = LoginResponse.fromJson(response);

      if (loginResponse.isSuccess) {
        // Guardar el token para futuras solicitudes
        _httpProvider.updateHeaders({
          'Authorization': 'Bearer ${loginResponse.token}',
        });

        // Siempre guardar la sesión, sin importar el valor de rememberMe
        await _saveSession(
            loginResponse.token, loginModel.usuario, loginResponse.idUsuario);

        // Mostrar mensaje de éxito
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loginResponse.message)),
          );

          // Navegar a la página principal con tabs
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeNavigation()),
          );
        }
      } else {
        // Mostrar mensaje de error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${loginResponse.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
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

  // Método para guardar la sesión
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
            // Fondo con degradado
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
            // Contenido
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 60),
                    // Logo o imagen
                    Container(
                      height: 120,
                      width: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryColor.withOpacity(0.3),
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
                    const SizedBox(height: 30),
                    // Título
                    const Text(
                      'SurveyGo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Subtítulo
                    const Text(
                      'Inicia sesión para continuar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textColor,
                      ),
                    ),
                    const SizedBox(height: 50),
                    // Formulario de login
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
                  ],
                ),
              ),
            ),
            // Indicador de carga
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
