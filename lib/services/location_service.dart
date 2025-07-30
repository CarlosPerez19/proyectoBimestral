import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _locationTimer;
  bool _isTracking = false;
  
  // Variables para optimización
  Position? _lastPosition;
  DateTime? _lastUpdateTime;
  
  // Configuración - Actualización cada 45 segundos para no sobrecargar la BD
  static const int _updateIntervalSeconds = 45;
  static const LocationAccuracy _desiredAccuracy = LocationAccuracy.medium; // Cambiado a medium para mejor rendimiento
  static const double _minimumDistanceFilter = 10.0; // Mínimo 10 metros de diferencia para actualizar

  /// Inicia el tracking de ubicación en tiempo real
  Future<void> startLocationTracking() async {
    if (_isTracking) return;

    try {
      // Crear perfil de usuario si no existe
      await _createUserProfile();

      _isTracking = true;
      
      // Intentar obtener ubicación, pero no fallar si no se puede
      try {
        // Verificar permisos de ubicación
        if (await _checkLocationPermissions()) {
          await _updateLocation();
        } else {
          debugPrint('⚠️ LocationService: Permisos de ubicación no disponibles, continuando sin GPS');
        }
      } catch (e) {
        debugPrint('⚠️ LocationService: GPS no disponible, continuando sin ubicación: $e');
      }
      
      // Configurar timer para actualizaciones periódicas (solo si tenemos permisos)
      _locationTimer = Timer.periodic(
        const Duration(seconds: _updateIntervalSeconds),
        (_) async {
          try {
            await _updateLocation();
          } catch (e) {
            debugPrint('⚠️ LocationService: Error en actualización periódica: $e');
          }
        },
      );

      debugPrint('🟢 LocationService: Tracking iniciado');
    } catch (e) {
      debugPrint('❌ LocationService: Error al iniciar tracking: $e');
      // No relanzar el error, permitir que la app continúe
    }
  }

  /// Detiene el tracking de ubicación
  Future<void> stopLocationTracking() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _isTracking = false;

    // Marcar usuario como offline
    try {
      await _supabase.from('user_locations').upsert({
        'user_id': _supabase.auth.currentUser?.id,
        'is_online': false,
        'last_seen': DateTime.now().toIso8601String(),
      });
      debugPrint('🔴 LocationService: Usuario marcado como offline');
    } catch (e) {
      debugPrint('❌ LocationService: Error al marcar offline: $e');
    }
  }

  /// Actualiza la ubicación actual del usuario
  Future<void> _updateLocation() async {
    try {
      if (!_isTracking) return;

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ LocationService: Usuario no autenticado');
        return;
      }

      debugPrint('📍 LocationService: Obteniendo ubicación actual...');
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: _desiredAccuracy,
        timeLimit: const Duration(seconds: 15), // Timeout más largo para Windows
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('Timeout obteniendo ubicación');
        },
      );

      debugPrint('📍 LocationService: Ubicación obtenida - Lat: ${position.latitude}, Lng: ${position.longitude}');

      // Optimización: Solo actualizar si hay cambio significativo
      bool shouldUpdate = true;
      
      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        
        // Solo actualizar si se movió más de la distancia mínima
        // O si han pasado más de 5 minutos desde la última actualización
        final timeSinceLastUpdate = _lastUpdateTime != null 
            ? DateTime.now().difference(_lastUpdateTime!).inMinutes 
            : 999;
            
        shouldUpdate = distance >= _minimumDistanceFilter || timeSinceLastUpdate >= 5;
      }

      if (shouldUpdate) {
        await _supabase.from('user_locations').upsert({
          'user_id': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'heading': position.heading,
          'is_online': true,
          'last_seen': DateTime.now().toIso8601String(),
        });

        // Actualizar variables de control
        _lastPosition = position;
        _lastUpdateTime = DateTime.now();

        debugPrint('📍 LocationService: Ubicación actualizada - ${position.latitude}, ${position.longitude}');
      } else {
        // Solo actualizar el timestamp de last_seen para mantener online
        await _supabase.from('user_locations').upsert({
          'user_id': userId,
          'is_online': true,
          'last_seen': DateTime.now().toIso8601String(),
        });
        
        debugPrint('⏰ LocationService: Solo actualizando last_seen (sin cambio de ubicación)');
      }
    } catch (e) {
      debugPrint('❌ LocationService: Error al actualizar ubicación: $e');
    }
  }

  /// Verifica y solicita permisos de ubicación
  Future<bool> _checkLocationPermissions() async {
    try {
      // En Windows, los servicios de ubicación pueden estar deshabilitados
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ LocationService: Servicios de ubicación deshabilitados');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('⚠️ LocationService: Permisos de ubicación denegados');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ LocationService: Permisos de ubicación denegados permanentemente');
        return false;
      }

      debugPrint('✅ LocationService: Permisos de ubicación concedidos');
      return true;
    } catch (e) {
      debugPrint('❌ LocationService: Error verificando permisos: $e');
      return false;
    }
  }

  /// Crea o actualiza el perfil del usuario
  Future<void> _createUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final deviceInfo = await _getDeviceInfo();

      await _supabase.from('user_profiles').upsert({
        'id': user.id,  // Cambio: usar 'id' en lugar de 'user_id'
        'email': user.email,
        'username': user.email?.split('@')[0] ?? 'Usuario',  // Cambio: usar 'username' que existe en la tabla
        'device_info': deviceInfo,
      });

      debugPrint('👤 LocationService: Perfil de usuario actualizado');
    } catch (e) {
      debugPrint('❌ LocationService: Error creando perfil: $e');
    }
  }

  /// Obtiene información del dispositivo
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      Map<String, dynamic> deviceData = {};

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceData = {
          'platform': 'Android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'version': androidInfo.version.release,
          'brand': androidInfo.brand,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceData = {
          'platform': 'iOS',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'version': iosInfo.systemVersion,
        };
      } else if (kIsWeb) {
        final webInfo = await deviceInfoPlugin.webBrowserInfo;
        deviceData = {
          'platform': 'Web',
          'browser': webInfo.browserName.name,
          'version': webInfo.appVersion,
        };
      } else {
        deviceData = {'platform': 'Unknown'};
      }

      return deviceData;
    } catch (e) {
      debugPrint('❌ LocationService: Error obteniendo info del dispositivo: $e');
      return {'platform': 'Unknown'};
    }
  }

  /// Obtiene ubicaciones de todos los usuarios online
  Stream<List<Map<String, dynamic>>> getUserLocations() {
    return _supabase
        .from('user_locations')
        .stream(primaryKey: ['id'])
        .eq('is_online', true)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  /// Obtiene información detallada de usuarios online
  Future<List<Map<String, dynamic>>> getOnlineUsersWithDetails() async {
    try {
      final response = await _supabase
          .from('user_locations')
          .select('''
            *,
            user_profiles (
              display_name,
              email,
              avatar_url,
              device_info
            )
          ''')
          .eq('is_online', true)
          .gte('last_seen', DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String());

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ LocationService: Error obteniendo usuarios online: $e');
      return [];
    }
  }

  /// Verifica si el servicio está activo
  bool get isTracking => _isTracking;

  /// Libera recursos
  void dispose() {
    stopLocationTracking();
  }
}
