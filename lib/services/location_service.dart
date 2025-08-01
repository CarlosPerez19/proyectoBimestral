import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _locationTimer;
  bool _isTracking = false;
  

  Position? _lastPosition;
  

  static const int _updateIntervalSeconds = 30; 
  static const LocationAccuracy _desiredAccuracy = LocationAccuracy.high;


  Future<bool> initialize() async {
    try {
      print('🔍 Verificando servicios de ubicación...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Los servicios de ubicación están deshabilitados');
        return false;
      }
      print('✅ Servicios de ubicación habilitados');

      print('🔍 Verificando permisos de ubicación...');
      LocationPermission permission = await Geolocator.checkPermission();
      print('📋 Permiso actual: $permission');
      
      if (permission == LocationPermission.denied) {
        print('🔐 Solicitando permisos de ubicación...');
        permission = await Geolocator.requestPermission();
        print('📋 Nuevo permiso: $permission');
        
        if (permission == LocationPermission.denied) {
          print('❌ Permisos de ubicación denegados por el usuario');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Permisos de ubicación denegados permanentemente');
        return false;
      }

      print('✅ LocationService inicializado correctamente con permiso: $permission');
      return true;
    } catch (e) {
      print('💥 Error inicializando LocationService: $e');
      return false;
    }
  }


  Future<void> startLocationTracking() async {
    if (_isTracking) {
      print('⚠️ LocationService ya está ejecutándose');
      return;
    }

    print('🚀 Iniciando LocationService...');
    bool initialized = await initialize();
    if (!initialized) {
      print('❌ No se pudo inicializar LocationService');
      return;
    }

    _isTracking = true;
    

    print('📍 Obteniendo ubicación inicial...');
    await _updateLocationPeriodic();
    

    _locationTimer = Timer.periodic(
      Duration(seconds: _updateIntervalSeconds), 
      (timer) {
        if (_isTracking) {
          print('⏰ Timer activado - Actualizando ubicación automáticamente');
          _updateLocationPeriodic();
        } else {
          print('⏰ Timer cancelado - LocationService detenido');
          timer.cancel();
        }
      }
    );

    print('✅ LocationService iniciado correctamente - Actualizaciones cada ${_updateIntervalSeconds}s');
  }

  Future<void> _updateLocationPeriodic() async {
    if (!_isTracking) {
      print('⚠️ LocationService no está activo, saltando actualización');
      return;
    }

    try {
      print('🎯 Obteniendo nueva posición GPS...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: _desiredAccuracy,
        timeLimit: Duration(seconds: 10), 
      );

      print('📍 GPS obtenido: ${position.latitude}, ${position.longitude} (±${position.accuracy}m)');
      await _processNewPosition(position);
    } catch (e) {
      print('❌ Error obteniendo posición GPS: $e');
      try {
        print('🔄 Reintentando con menor precisión...');
        Position fallbackPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        );
        print('📍 GPS fallback obtenido: ${fallbackPosition.latitude}, ${fallbackPosition.longitude}');
        await _processNewPosition(fallbackPosition);
      } catch (fallbackError) {
        print('💥 Error total obteniendo GPS: $fallbackError');
      }
    }
  }


  Future<void> _processNewPosition(Position position) async {
    print('🔄 Procesando nueva posición...');
    

    await _savePositionToDatabase(position);
    _lastPosition = position;
    
    print('✅ Posición procesada y guardada exitosamente');
  }

  Future<void> _savePositionToDatabase(Position position) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        print('❌ No hay usuario autenticado para guardar ubicación');
        return;
      }

      final now = DateTime.now().toIso8601String();

      print('💾 === GUARDANDO UBICACIÓN ===');
      print('👤 Usuario: ${user.id}');
      print('📍 Lat: ${position.latitude}');
      print('📍 Lng: ${position.longitude}');
      print('⏰ Tiempo: $now');

      try {
        print('🎯 Intentando UPSERT en user_locations...');
        
        final result = await _supabase.from('user_locations').upsert({
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
        
        print('✅ ÉXITO: Guardado en user_locations con UPSERT');
        print('📋 Resultado: $result');
        
      } catch (upsertError) {
        print('❌ UPSERT falló: $upsertError');
        print('🔄 Intentando INSERT como alternativa...');
        
        try {
          await _supabase.from('user_locations').insert({
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
          print('✅ RECUPERADO: INSERT exitoso en user_locations');
          
        } catch (insertError) {
          print('💥 FALLO TOTAL: INSERT también falló: $insertError');
          
          try {
            final updateResult = await _supabase
                .from('user_locations')
                .update({
                  'latitude': position.latitude,
                  'longitude': position.longitude,
                  'accuracy': position.accuracy,
                  'heading': position.heading,
                  'speed': position.speed,
                  'is_online': true,
                  'last_seen': now,
                  'updated_at': now,
                })
                .eq('user_id', user.id);
                
            print('✅ ÚLTIMO RECURSO: UPDATE exitoso: $updateResult');
            
          } catch (updateError) {
            print('� ERROR CRÍTICO: Ningún método funcionó: $updateError');
          }
        }
      }

      try {
        await _supabase.from('user_profiles').upsert({
          'id': user.id,
          'email': user.email,
          'username': user.email?.split('@')[0] ?? 'Usuario',
          'is_online': true,
          'updated_at': now,
        });
        print('✅ Perfil actualizado como ACTIVO');
      } catch (profileError) {
        print('⚠️ Error actualizando perfil (no crítico): $profileError');
      }

      print('💾 === FIN GUARDADO UBICACIÓN ===');
      
    } catch (e) {
      print('💥 ERROR GENERAL en _savePositionToDatabase: $e');
    }
  }

  Future<void> stopLocationTracking() async {
    _isTracking = false;
    _locationTimer?.cancel();
    _locationTimer = null;
    
    if (kDebugMode) {
      print('Seguimiento de ubicación detenido');
    }
  }

  Future<Position?> getCurrentPosition() async {
    try {
      print('🎯 Iniciando getCurrentPosition...');
      
      bool initialized = await initialize();
      if (!initialized) {
        print('❌ No se pudo inicializar LocationService');
        return null;
      }

      print('🔍 LocationService inicializado, obteniendo posición...');

      try {
        print('📱 Intentando obtener última posición conocida...');
        Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          DateTime now = DateTime.now();
          Duration timeDiff = now.difference(lastKnown.timestamp);
          
          print('⏰ Última posición: ${timeDiff.inSeconds} segundos de antigüedad');
          
          if (timeDiff.inMinutes < 2) {
            print('✅ Usando última posición conocida: ${lastKnown.latitude}, ${lastKnown.longitude}');
            return lastKnown;
          } else {
            print('⚠️ Última posición muy antigua (${timeDiff.inMinutes} min), obteniendo nueva...');
          }
        } else {
          print('⚠️ No hay última posición conocida disponible');
        }
      } catch (e) {
        print('⚠️ Error obteniendo última posición conocida: $e');
      }

      List<LocationAccuracy> accuracyLevels = [
        LocationAccuracy.medium,   
        LocationAccuracy.low,       
        LocationAccuracy.lowest,   
      ];

      for (int i = 0; i < accuracyLevels.length; i++) {
        LocationAccuracy accuracy = accuracyLevels[i];
        int timeoutSeconds = 5 + (i * 5); 
        
        try {
          print('🎯 Intento ${i + 1}/3 - Precisión: $accuracy, Timeout: ${timeoutSeconds}s');
          
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: accuracy,
            timeLimit: Duration(seconds: timeoutSeconds),
          );
          
          print('✅ ¡Posición obtenida exitosamente!');
          print('📍 Coordenadas: ${position.latitude}, ${position.longitude}');
          print('🎯 Precisión: ${position.accuracy}m');
          print('⏰ Timestamp: ${position.timestamp}');
          
          return position;
          
        } catch (e) {
          print('❌ Intento ${i + 1} falló con $accuracy: $e');
          if (i == accuracyLevels.length - 1) {
            print('💥 Todos los intentos de obtener posición fallaron');
          } else {
            print('🔄 Intentando con menor precisión...');
          }
        }
      }

      print('❌ No se pudo obtener posición GPS con ningún método');
      return null;
      
    } catch (e) {
      print('💥 Error general en getCurrentPosition: $e');
      return null;
    }
  }

  void dispose() {
    stopLocationTracking();
  }

  bool get isTracking => _isTracking;
  Position? get lastKnownPosition => _lastPosition;
}
