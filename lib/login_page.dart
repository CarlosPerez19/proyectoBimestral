import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final usernameController = TextEditingController();
  final supabase = Supabase.instance.client;
  bool isLogin = true;
  String selectedRole = 'user';
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (isLoading) return;
    
    try {
      setState(() => isLoading = true);
      
      if (emailController.text.isEmpty || passwordController.text.isEmpty) {
        _showError('Por favor llena todos los campos');
        return;
      }

      _showLoadingMessage('Iniciando sesión...');

      final response = await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (response.user != null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSuccess('¡Sesión iniciada correctamente!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error en login: $e');
      }
      _handleAuthError(e);
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> signUp() async {
    if (isLoading) return;
    
    try {
      setState(() => isLoading = true);
      
      if (emailController.text.isEmpty || 
          passwordController.text.isEmpty || 
          usernameController.text.isEmpty) {
        _showError('Por favor llena todos los campos');
        return;
      }

      if (usernameController.text.length < 3) {
        _showError('El nombre de usuario debe tener al menos 3 caracteres');
        return;
      }

      if (passwordController.text.length < 6) {
        _showError('La contraseña debe tener al menos 6 caracteres');
        return;
      }

      _showLoadingMessage('Creando cuenta...');

      final response = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
        data: {
          'username': usernameController.text.trim(),
          'role': selectedRole,
        },
      );

      if (response.user != null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        await Future.delayed(const Duration(milliseconds: 1000));
        
        await _createUserProfile(response.user!);
        
        _showSuccess('¡Cuenta creada exitosamente!');
        
        if (mounted) {
          setState(() {
            isLogin = true;
            passwordController.clear();
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error en registro: $e');
      }
      _handleAuthError(e);
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _createUserProfile(User user) async {
    try {
      if (kDebugMode) {
        print('Creando perfil manual para: ${user.email}');
        print('Username: ${usernameController.text.trim()}');
        print('Role: $selectedRole');
      }

      await supabase.from('user_profiles').upsert({
        'id': user.id,
        'email': user.email,
        'username': usernameController.text.trim(),
        'is_online': false,
      });

      await supabase.from('user_roles').upsert({
        'user_id': user.id,
        'role': selectedRole,
      });

      if (kDebugMode) {
        print('Perfil y rol creados manualmente exitosamente');
      }

      final profile = await supabase
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (kDebugMode) {
        print('Perfil verificado: $profile');
      }

      if (profile['role'] != selectedRole) {
        if (kDebugMode) {
          print('Rol incorrecto, usando función SQL para corrección...');
        }
        
        await supabase.rpc('fix_user_role', params: {
          'user_email': user.email,
          'new_role': selectedRole,
        });
      }

    } catch (e) {
      if (kDebugMode) {
        print('Error creando perfil manual: $e');
      }

    }
  }

  void _handleAuthError(dynamic e) {
    String message = 'Error desconocido';
    
    if (e is AuthException) {
      switch (e.message.toLowerCase()) {
        case 'invalid login credentials':
          message = 'Credenciales incorrectas';
          break;
        case 'user already registered':
          message = 'El usuario ya está registrado';
          break;
        case 'signup disabled':
          message = 'El registro está deshabilitado';
          break;
        case 'email rate limit exceeded':
          message = 'Demasiados intentos. Espera unos minutos.';
          break;
        default:
          message = e.message;
      }
    } else {
      message = e.toString();
    }
    
    _showError(message);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showLoadingMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.blue[600],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      isLogin ? 'Iniciar Sesión' : 'Crear Cuenta',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isLogin 
                        ? 'Ingresa tus credenciales'
                        : 'Completa el formulario para registrarte',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 30),

                    if (!isLogin) ...[
                      TextField(
                        controller: usernameController,
                        enabled: !isLoading,
                        decoration: InputDecoration(
                          labelText: 'Nombre de usuario',
                          hintText: 'Ej: juan_perez',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.blue[600]!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextField(
                      controller: emailController,
                      enabled: !isLoading,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        hintText: 'ejemplo@correo.com',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.blue[600]!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: passwordController,
                      enabled: !isLoading,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        hintText: 'Mínimo 6 caracteres',
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.blue[600]!),
                        ),
                      ),
                    ),

                    if (!isLogin) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tipo de usuario',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: RadioListTile<String>(
                                    title: const Row(
                                      children: [
                                        Icon(Icons.person, size: 20),
                                        SizedBox(width: 8),
                                        Text('Usuario'),
                                      ],
                                    ),
                                    subtitle: const Text('Topógrafo/Operador'),
                                    value: 'user',
                                    groupValue: selectedRole,
                                    onChanged: isLoading ? null : (value) {
                                      if (value != null) {
                                        setState(() => selectedRole = value);
                                      }
                                    },
                                    dense: true,
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<String>(
                                    title: const Row(
                                      children: [
                                        Icon(Icons.admin_panel_settings, size: 20),
                                        SizedBox(width: 8),
                                        Text('Admin'),
                                      ],
                                    ),
                                    subtitle: const Text('Administrador'),
                                    value: 'admin',
                                    groupValue: selectedRole,
                                    onChanged: isLoading ? null : (value) {
                                      if (value != null) {
                                        setState(() => selectedRole = value);
                                      }
                                    },
                                    dense: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : (isLogin ? login : signUp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isLogin ? 'Iniciar Sesión' : 'Crear Cuenta',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextButton(
                      onPressed: isLoading ? null : () {
                        setState(() {
                          isLogin = !isLogin;
                          passwordController.clear();
                          if (isLogin) {
                            usernameController.clear();
                            selectedRole = 'user';
                          }
                        });
                      },
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(color: Colors.grey[600]),
                          children: [
                            TextSpan(
                              text: isLogin 
                                ? '¿No tienes cuenta? '
                                : '¿Ya tienes cuenta? ',
                            ),
                            TextSpan(
                              text: isLogin ? 'Regístrate' : 'Inicia sesión',
                              style: TextStyle(
                                color: Colors.blue[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (kDebugMode && !isLogin) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Debug Info:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Rol seleccionado: $selectedRole',
                              style: const TextStyle(fontSize: 11),
                            ),
                            Text(
                              'Username: ${usernameController.text}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}