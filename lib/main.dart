import 'package:flutter/material.dart';
import 'package:proyectobimestral/tracking_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import 'tracking_page.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://wnqsjkihjznujutqvfjs.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InducXNqa2loanpudWp1dHF2ZmpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI3Nzg5MTEsImV4cCI6MjA2ODM1NDkxMX0.IHmiQ-bbjzG8ueYV8U0SPBihcIIhEhE4pOPKWfigc7c',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supabase Upload App',
      theme: ThemeData(primarySwatch: Colors.blue),
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
          return TrackingPage(); 
        } else {
          return LoginPage(); 
        }
      },
    );
  }
}