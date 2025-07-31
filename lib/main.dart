import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import 'tracking_page_improved.dart';
import 'admin_page_improved.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar Supabase
  await Supabase.initialize(
    url: 'https://flirdfwwgaaohzbxnpju.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZsaXJkZnd3Z2Fhb2h6YnhucGp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDg2NDcyOTYsImV4cCI6MjA2NDIyMzI5Nn0.kZj7S6-l7No1gTE5Hb5ETGSj-cdNDZC1N8JJubYsuDg',
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistema de Tracking Topográfico',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const RoleBasedRouter();
        } else {
          return const LoginPage(); 
        }
      },
    );
  }
}

class RoleBasedRouter extends StatefulWidget {
  const RoleBasedRouter({super.key});

  @override
  State<RoleBasedRouter> createState() => _RoleBasedRouterState();
}

class _RoleBasedRouterState extends State<RoleBasedRouter> {
  String? userRole;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _getUserRole();
  }

  Future<void> _getUserRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Consultar directamente la tabla user_roles
        final response = await Supabase.instance.client
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id)
            .maybeSingle();
        
        if (response != null) {
          // Manejo seguro del tipo de datos
          final roleValue = response['role'];
          final roleString = roleValue != null ? roleValue.toString() : 'user';
          
          setState(() {
            userRole = roleString;
            isLoading = false;
          });
        } else {
          // Si no existe rol, crear uno por defecto
          try {
            await Supabase.instance.client
                .from('user_roles')
                .insert({
                  'user_id': user.id,
                  'role': 'user',
                });
          } catch (insertError) {
            print('Error insertando rol: $insertError');
          }
          
          setState(() {
            userRole = 'user';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          userRole = null;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error obteniendo rol: $e');
      setState(() {
        userRole = 'user'; // Default role si hay error
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.blue[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
              ),
              const SizedBox(height: 20),
              Text(
                'Cargando...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mostrar la pantalla según el rol del usuario
    if (userRole == 'admin') {
      return const AdminPageImproved();
    } else {
      return const TrackingPageImproved();
    }
  }
}