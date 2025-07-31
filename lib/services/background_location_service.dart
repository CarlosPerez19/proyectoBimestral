import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _backgroundTimer;
  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;
  
  // Variables para optimización
  Position? _lastPosition;
  DateTime? _lastUpdateTime;
  
  // Configuración optimizada para background
  static const int _backgroundUpdateInterval = 30; // 30 segundos
  static const LocationAccuracy _accuracy = LocationAccuracy.high;
  static const int _distanceFilter = 5; // 5 metros mínimo (como int)

  /// Inicia el tracking de ubicación mejorado para background
  Future<void> startBackgroundTracking() async {
    if (_isTracking) return;

    try {
      // Verificar permisos
      if (!await _checkLocationPermissions()) {
        debugPrint('❌ BackgroundLocationService: Sin permisos de ubicación');
        return;
      }

      _isTracking = true;
      await _createUserProfile();
      
      // Iniciar stream de posición con configuración optimizada
      await _startPositionStream();
      
      // Timer de respaldo para actualizaciones en background
      _startBackgroundTimer();
      
      debugPrint('🟢 BackgroundLocationService: Iniciado con éxito');
    } catch (e) {
      debugPrint('❌ BackgroundLocationService: Error al iniciar: $e');
    }
  }

  /// Inicia el stream de posición optimizado
  Future<void> _startPositionStream() async {
    try {
      const locationSettings = LocationSettings(
        accuracy: _accuracy,
        distanceFilter: _distanceFilter,
        timeLimit: Duration(seconds: 8),
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) async {
          await _handlePositionUpdate(position, 'stream');
        },
        onError: (error) {
          debugPrint('⚠️ BackgroundLocationService: Error en stream: $error');
        },
      );

      debugPrint('📡 BackgroundLocationService: Position stream iniciado');
    } catch (e) {
      debugPrint('❌ BackgroundLocationService: Error iniciando stream: $e');
    }
  }

  /// Timer de respaldo para asegurar actualizaciones en background
  void _startBackgroundTimer() {
    _backgroundTimer = Timer.periodic(
      Duration(seconds: _backgroundUpdateInterval),
      (_) async {
        if (_isTracking) {
          try {
            final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: _accuracy,
              timeLimit: Duration(seconds: 8),
            );
            await _handlePositionUpdate(position, 'timer');
          } catch (e) {
            debugPrint('⚠️ BackgroundLocationService: Error en timer: $e');
          }
        }
      },
    );
    debugPrint('⏰ BackgroundLocationService: Timer de respaldo iniciado');
  }

  /// Maneja las actualizaciones de posición
  Future<void> _handlePositionUpdate(Position position, String source) async {
    if (!_isTracking) return;

    try {
      final now = DateTime.now();
      
      // Verificar si necesitamos actualizar
      if (_shouldUpdatePosition(position, now)) {
        await _updateLocationInDatabase(position);
        _lastPosition = position;
        _lastUpdateTime = now;
        
        debugPrint('📍 [$source] Posición actualizada: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)} (±${position.accuracy.toStringAsFixed(1)}m)');
      }
    } catch (e) {
      debugPrint('❌ BackgroundLocationService: Error actualizando posición: $e');
    }
  }

  /// Verifica si debemos actualizar la posición
  bool _shouldUpdatePosition(Position newPosition, DateTime now) {
    if (_lastPosition == null || _lastUpdateTime == null) {
      return true;
    }

    // Verificar distancia
    double distance = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      newPosition.latitude,
      newPosition.longitude,
    );

    // Criterios de actualización más estrictos para topografía
    bool significantDistance = distance >= _distanceFilter;
    bool significantTime = now.difference(_lastUpdateTime!).inSeconds >= 30; // 30 segundos
    bool accuracyImproved = newPosition.accuracy < (_lastPosition!.accuracy - 2);

    return significantDistance || significantTime || accuracyImproved;
  }

  /// Actualiza la ubicación en la base de datos
  Future<void> _updateLocationInDatabase(Position position) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now().toIso8601String();

      debugPrint('💾 BackgroundService: Guardando ubicación en BD...');
      debugPrint('👤 Usuario: $userId');
      debugPrint('📍 Lat: ${position.latitude}, Lng: ${position.longitude}');

      await _supabase.from('user_locations').upsert({
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'is_online': true,
        'last_seen': now,
        'updated_at': now,
      });

      debugPrint('✅ BackgroundService: Ubicación guardada exitosamente');

      // También actualizar perfil como online
      await _supabase.from('user_profiles').update({
        'is_online': true,
        'updated_at': now,
      }).eq('id', userId);

      debugPrint('✅ BackgroundService: Perfil actualizado como activo');

    } catch (e) {
      debugPrint('❌ BackgroundLocationService: Error guardando en BD: $e');
    }
  }

  /// Detiene el tracking
  Future<void> stopBackgroundTracking() async {
    _isTracking = false;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    await _positionStream?.cancel();
    _positionStream = null;

    // Marcar como offline
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _supabase.from('user_locations').upsert({
          'user_id': userId,
          'is_online': false,
          'last_seen': DateTime.now().toIso8601String(),
        });

        await _supabase.from('user_profiles').update({
          'is_online': false,
        }).eq('id', userId);
      }
    } catch (e) {
      debugPrint('❌ BackgroundLocationService: Error marcando offline: $e');
    }

    debugPrint('🔴 BackgroundLocationService: Detenido');
  }

  /// Verifica permisos de ubicación
  Future<bool> _checkLocationPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('❌ Servicios de ubicación deshabilitados');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('❌ Permisos de ubicación denegados');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ Permisos de ubicación denegados permanentemente');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error verificando permisos: $e');
      return false;
    }
  }

  /// Crea perfil de usuario si no existe
  Future<void> _createUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Verificar si el perfil existe
      final existingProfile = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile == null) {
        // Crear perfil
        await _supabase.from('user_profiles').insert({
          'id': user.id,
          'email': user.email,
          'username': user.email?.split('@')[0] ?? 'Usuario',
          'is_online': true,
        });
        debugPrint('✅ Perfil de usuario creado');
      }
    } catch (e) {
      debugPrint('❌ Error creando perfil: $e');
    }
  }

  /// Dispose del servicio
  void dispose() {
    stopBackgroundTracking();
  }

  /// Getter para verificar si está tracking
  bool get isTracking => _isTracking;

  /// Getter para última posición
  Position? get lastPosition => _lastPosition;
}
