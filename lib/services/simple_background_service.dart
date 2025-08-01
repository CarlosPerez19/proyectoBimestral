import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SimpleBackgroundService {
  static StreamSubscription<Position>? _positionStream;
  static Timer? _backupTimer;
  static Timer? _streamRestartTimer;
  static bool _isRunning = false;
  static Position? _lastKnownPosition;
  static DateTime? _lastStreamSuccess;

  static Future<void> initialize() async {
    debugPrint('📱 SimpleBackgroundService: Inicializando servicio simple...');

    if (defaultTargetPlatform == TargetPlatform.android) {
      GeolocatorAndroid.registerWith();
    }
  }

  static Future<void> startBackgroundTracking() async {
    if (_isRunning) {
      debugPrint('⚠️ SimpleBackgroundService: Ya está ejecutándose');
      return;
    }

    try {
      debugPrint('🚀 SimpleBackgroundService: Iniciando tracking optimizado para segundo plano');

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('❌ SimpleBackgroundService: GPS desactivado');
        throw Exception('El servicio de GPS está desactivado');
      }

      LocationPermission permission = await _checkAndRequestPermissions();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        debugPrint('❌ SimpleBackgroundService: Sin permisos de ubicación');
        throw Exception('Permisos de ubicación denegados');
      }

      debugPrint('✅ Permisos verificados: $permission');

      _isRunning = true;

      await _startLocationStream();

      _streamRestartTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
        if (_lastStreamSuccess == null || 
            DateTime.now().difference(_lastStreamSuccess!).inMinutes >= 2) {
          debugPrint('🔄 Stream inactivo >2min, reiniciando...');
          await _restartLocationStream();
        }
      });


      await _getInitialLocation();

      debugPrint('⏰ Timer: Respaldo cada 40s si el stream falla');
      _backupTimer = Timer.periodic(const Duration(seconds: 40), (timer) async {
        if (_lastStreamSuccess == null || 
            DateTime.now().difference(_lastStreamSuccess!).inMinutes >= 1) {
          debugPrint('⚠️ Stream inactivo >1min, ejecutando respaldo completo...');
          await _performLocationUpdate();
        } else {
          final minutesAgo = DateTime.now().difference(_lastStreamSuccess!).inMinutes;
          debugPrint('✅ Stream activo (hace ${minutesAgo}min), saltando respaldo');
        }
      });

      debugPrint('✅ Sistema de ubicación en segundo plano iniciado');
    } catch (e) {
      debugPrint('❌ Error iniciando servicio: $e');
      _isRunning = false;
    }
  }

  static Future<LocationPermission> _checkAndRequestPermissions() async {
    debugPrint('🔐 Verificando permisos de ubicación...');
    
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('📱 Permiso actual: $permission');
    
    if (permission == LocationPermission.denied) {
      debugPrint('⚠️ Permiso denegado, solicitando...');
      permission = await Geolocator.requestPermission();
      debugPrint('📱 Permiso después de solicitar: $permission');
    }
    
    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Permiso denegado permanentemente');
      throw Exception('Los permisos de ubicación han sido denegados permanentemente. Por favor, habilítalos en la configuración de la aplicación.');
    }
    
    if (defaultTargetPlatform == TargetPlatform.android && permission == LocationPermission.whileInUse) {
      debugPrint('⚠️ Permiso de uso en primer plano concedido. Verificando el de segundo plano...');
      
      final backgroundPermissionStatus = await Geolocator.checkPermission();
      if (backgroundPermissionStatus == LocationPermission.whileInUse || backgroundPermissionStatus == LocationPermission.denied) {
        debugPrint('⚠️ Solicitando permiso de ubicación en segundo plano (Android 10+)...');
        final newPermission = await Geolocator.requestPermission();
        debugPrint('📱 Permiso después de solicitar el de segundo plano: $newPermission');

        if (newPermission == LocationPermission.whileInUse) {
          debugPrint('❌ El usuario no concedió el permiso de ubicación en segundo plano. El servicio será menos fiable.');
        }
      }
    }

    if (permission == LocationPermission.denied) {
      debugPrint('❌ Permiso denegado por el usuario');
      throw Exception('Los permisos de ubicación son necesarios para el funcionamiento de la aplicación.');
    }
    
    debugPrint('✅ Permisos de ubicación verificados correctamente');
    return permission;
  }

  static Future<void> stopBackgroundTracking() async {
    debugPrint('🛑 Deteniendo servicio...');
    await _positionStream?.cancel();
    _positionStream = null;
    _backupTimer?.cancel();
    _backupTimer = null;
    _streamRestartTimer?.cancel();
    _streamRestartTimer = null;
    _isRunning = false;
    debugPrint('✅ Servicio detenido');
  }

  static bool get isRunning => _isRunning;

  static Future<LocationPermission> checkLocationPermission() async {
    return await Geolocator.checkPermission();
  }

  static Future<LocationPermission> requestLocationPermission() async {
    return await Geolocator.requestPermission();
  }

  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  static Future<Map<String, dynamic>> getLocationStatus() async {
    final permission = await Geolocator.checkPermission();
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    return {
      'permission': permission.toString(),
      'serviceEnabled': serviceEnabled,
      'isRunning': _isRunning,
      'lastUpdate': _lastStreamSuccess?.toIso8601String(),
      'hasLastKnownPosition': _lastKnownPosition != null,
    };
  }

  static Future<void> _startLocationStream() async {
    try {
      debugPrint('📡 Iniciando stream GPS optimizado con getPositionStream()...');
      await _positionStream?.cancel();
      
      LocationSettings locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          timeLimit: const Duration(seconds: 30),

          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: "Tu app está usando tu ubicación",
            notificationText: "La app necesita tu ubicación para funcionar correctamente en segundo plano.",
            setOngoing: true,
            enableWakeLock: true,
          ),
        );
        debugPrint('💡 Sugerencia: Asegúrate de que el archivo AndroidManifest.xml contenga la etiqueta "foregroundServiceType".');
      }
      
      debugPrint('⚙️ Configuración del stream:');
      debugPrint('   • Precisión: Alta (LocationAccuracy.high)');
      debugPrint('   • Filtro de distancia: 10 metros');
      debugPrint('   • Timeout por actualización: 30 segundos');
      debugPrint('   • **Foreground Service Habilitado **');
      
      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          debugPrint('🎯 Stream GPS activo: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}');
          debugPrint('   • Precisión: ±${position.accuracy.toStringAsFixed(1)}m');
          debugPrint('   • Velocidad: ${position.speed.toStringAsFixed(1)} m/s');
          debugPrint('   • Rumbo: ${position.heading.toStringAsFixed(0)}°');
          
          _lastKnownPosition = position;
          _lastStreamSuccess = DateTime.now();
          _saveLocationToDatabase(position);
        },
        onError: (error) {
          debugPrint('⚠️ Error en stream GPS: $error');
          debugPrint('🔄 El stream se reiniciará automáticamente...');
        },
        onDone: () {
          debugPrint('📡 Stream GPS finalizado');
        },
      );
      
      debugPrint('✅ Stream GPS iniciado exitosamente con getPositionStream()');
    } catch (e) {
      debugPrint('❌ Error iniciando stream GPS: $e');
      rethrow;
    }
  }

  static Future<void> _restartLocationStream() async {
    debugPrint('🔄 Reiniciando stream GPS...');
    await _positionStream?.cancel();
    await Future.delayed(const Duration(seconds: 2));
    await _startLocationStream();
  }


  static Future<void> _getInitialLocation() async {
    try {
      debugPrint('🎯 Obteniendo ubicación inicial...');
      
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint('📍 Usando última ubicación conocida como inicial: ${lastKnown.latitude}, ${lastKnown.longitude}');
        _lastKnownPosition = lastKnown;
        _lastStreamSuccess = DateTime.now();
        await _saveLocationToDatabase(lastKnown);
      } else {
        debugPrint('⚠️ Sin ubicación conocida, obteniendo nueva...');
        await _performLocationUpdate();
      }
    } catch (e) {
      debugPrint('❌ Error obteniendo ubicación inicial: $e');
    }
  }

  static Future<void> _performLocationUpdate() async {
    debugPrint('🔄 Timer ejecutándose - Obteniendo posición...');
    
    try {
      Position? position;
      
      debugPrint('📡 Intentando obtener posición con precisión media (60s de espera)...');
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 60),
      );
      debugPrint('✅ GPS exitoso: ${position.latitude}, ${position.longitude}');
      
      if (position != null) {
        _lastKnownPosition = position;
        _lastStreamSuccess = DateTime.now();
        await _saveLocationToDatabase(position);
        debugPrint('🎉 Actualización exitosa: ${position.latitude}, ${position.longitude}');
      }
      
    } catch (e) {
      debugPrint('💥 Falló el intento principal: $e');
      
      try {
        debugPrint('🔄 Buscando última ubicación conocida del sistema...');
        Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          debugPrint('📍 Última conocida del sistema: ${lastKnown.latitude}, ${lastKnown.longitude}');
          _lastKnownPosition = lastKnown;
          _lastStreamSuccess = DateTime.now();
          await _saveLocationToDatabase(lastKnown);
        } else {

          if (_lastKnownPosition != null) {
            debugPrint('📍 Usando nuestra última posición guardada: ${_lastKnownPosition!.latitude}, ${_lastKnownPosition!.longitude}');
            _lastStreamSuccess = DateTime.now();
            await _saveLocationToDatabase(_lastKnownPosition!);
          } else {
            debugPrint('❌ No hay ninguna ubicación disponible');
          }
        }
      } catch (e2) {
        debugPrint('❌ Error total al obtener ubicación: $e2');
      }
    }
  }

  static Future<void> _saveLocationToDatabase(Position position) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('❌ Usuario no autenticado - no se puede guardar');
        return;
      }

      final now = DateTime.now().toIso8601String();

      await _saveWithRetry(() async {
        await supabase.from('user_locations').upsert({
          'user_id': user.id,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'heading': position.heading,
          'speed': position.speed,
          'is_online': true,
          'last_seen': now,
          'updated_at': now,
        });

        await supabase.from('user_profiles').upsert({
          'id': user.id,
          'email': user.email,
          'username': user.email?.split('@')[0] ?? 'Usuario',
          'is_online': true,
          'updated_at': now,
        });

        debugPrint('🎉 ¡Ubicación guardada en Supabase!');
      });
    } catch (e) {
      debugPrint('💥 Error al guardar en BD: $e');
    }
  }

  static Future<void> _saveWithRetry(
    Future<void> Function() operation, {
    int maxRetries = 3,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        await operation();
        return;
      } catch (e) {
        debugPrint('❌ Intento ${i + 1}/$maxRetries fallido: $e');
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
  }
}
