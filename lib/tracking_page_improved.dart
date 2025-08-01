import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import './services/location_service.dart';
import './services/simple_background_service.dart';
import 'admin_page_improved.dart';

class TrackingPageImproved extends StatefulWidget {
  const TrackingPageImproved({super.key});

  @override
  State<TrackingPageImproved> createState() => _TrackingPageImprovedState();
}

class _TrackingPageImprovedState extends State<TrackingPageImproved> {
  final supabase = Supabase.instance.client;
  late final LocationService locationService;
  List<LatLng> devicePositions = [];
  List<Map<String, dynamic>> positionData = [];
  List<Map<String, dynamic>> onlineUsers = [];
  List<Map<String, dynamic>> allUsers = []; 
  double area = 0;
  List<Map<String, dynamic>> projects = [];
  String? selectedProjectId;
  String? userRole;
  Map<String, dynamic>? currentUser;
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  StreamSubscription? _positionsSubscription;
  StreamSubscription? _userLocationsSubscription;
  StreamSubscription? _userProfilesSubscription;
  Timer? _locationUpdateTimer; 
  DateTime? _lastUpdateTime; 

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    _checkLocationPermissions(); 
    _loadUserProfile();
    _loadProjects();
    _startLocationService();
  }

  Future<void> _checkLocationPermissions() async {
    try {
      final status = await SimpleBackgroundService.getLocationStatus();
      debugPrint('📱 Estado de ubicación: $status');
      
      if (!status['serviceEnabled']) {
        _showLocationServiceDialog();
        return;
      }
      
      final permission = status['permission'];
      if (permission.contains('denied')) {
        _showPermissionDialog();
      }
    } catch (e) {
      debugPrint('❌ Error verificando permisos: $e');
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('GPS Desactivado'),
        content: const Text(
          'El servicio de GPS está desactivado. Por favor, actívalo en la configuración de tu dispositivo para usar esta aplicación.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Abrir Configuración'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permisos de Ubicación'),
        content: const Text(
          'Esta aplicación necesita acceso a tu ubicación para funcionar correctamente. Por favor, concede los permisos necesarios.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final permission = await SimpleBackgroundService.requestLocationPermission();
              if (permission != LocationPermission.denied && 
                  permission != LocationPermission.deniedForever) {
                _startLocationService();
              }
            },
            child: const Text('Conceder Permisos'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {

    _positionsSubscription?.cancel();
    _userLocationsSubscription?.cancel();
    _userProfilesSubscription?.cancel();
    _locationUpdateTimer?.cancel(); 
    locationService.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        debugPrint('👤 Cargando perfil para usuario: ${user.id}');
        
        final profile = await supabase
            .from('user_profiles')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();

        final roleData = await supabase
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id)
            .maybeSingle();

        if (profile != null) {
          debugPrint('✅ Perfil existente encontrado');
          setState(() {
            currentUser = {...profile, 'role': roleData?['role'] ?? 'user'};
            userRole = roleData?['role'] ?? 'user';
          });
        } else {
          debugPrint('⚠️ Perfil no existe, creando nuevo perfil...');
          final now = DateTime.now().toIso8601String();
          
          await supabase.from('user_profiles').upsert({
            'id': user.id,
            'email': user.email,
            'username': user.email?.split('@')[0] ?? 'Usuario',
            'is_online': true, 
            'created_at': now,
            'updated_at': now,
          });
          debugPrint('✅ Nuevo perfil creado y ACTIVADO');

          await supabase.from('user_roles').upsert({
            'user_id': user.id,
            'role': 'user',
          });
          debugPrint('✅ Rol de usuario asignado');

          setState(() {
            currentUser = {
              'id': user.id,
              'email': user.email,
              'username': user.email?.split('@')[0] ?? 'Usuario',
              'is_online': true, 
              'role': 'user',
            };
            userRole = 'user';
          });
          
          debugPrint('🎉 USUARIO NUEVO LISTO - Debería aparecer en el mapa');
        }
        
        if (currentUser?['is_online'] != true) {
          debugPrint('🔄 Activando usuario que estaba inactivo...');
          await supabase.from('user_profiles').update({
            'is_online': true,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', user.id);
          
          if (mounted) {
            setState(() {
              currentUser = {...(currentUser ?? {}), 'is_online': true};
            });
          }
          debugPrint('✅ Usuario reactivado');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading user profile: $e');
    }
  }

  Future<void> _startLocationService() async {
    try {
      debugPrint('🚀 INICIANDO SERVICIOS DE UBICACIÓN...');
      
      debugPrint('📱 Iniciando LocationService principal...');
      await locationService.startLocationTracking();
      debugPrint('✅ LocationService principal iniciado');
      
      debugPrint('🌟 Iniciando SimpleBackgroundService...');
      await SimpleBackgroundService.startBackgroundTracking();
      debugPrint('✅ SimpleBackgroundService iniciado');
      
      debugPrint('✅ Servicios de ubicación iniciados (foreground + background)');
      debugPrint('🔄 Las ubicaciones se actualizarán automáticamente cada 30 segundos');
      
      debugPrint('🚀 Forzando actualización inicial...');
      await _forceLocationUpdate();
      
      debugPrint('⏰ Verificando que el timer esté activo...');
      Future.delayed(Duration(seconds: 35), () {
        debugPrint('🔍 Verificación: ¿El LocationService está enviando datos cada 30s?');
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Servicios de ubicación iniciados correctamente'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      debugPrint('❌ LocationService error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error GPS: $e'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _forceLocationUpdate() async {
    try {
      debugPrint('🚀 Forzando actualización de ubicación...');
      final position = await locationService.getCurrentPosition();
      if (position != null) {
        debugPrint('📍 Ubicación forzada obtenida: ${position.latitude}, ${position.longitude}');
        
        final user = supabase.auth.currentUser;
        if (user != null) {
          final now = DateTime.now().toIso8601String();
          try {
            debugPrint('💾 Guardando manualmente en user_locations...');
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
            debugPrint('✅ Usuario forzado a aparecer en user_locations');
            

            await supabase.from('user_profiles').upsert({
              'id': user.id,
              'email': user.email,
              'username': user.email?.split('@')[0] ?? 'Usuario',
              'is_online': true,
              'updated_at': now,
            });
            debugPrint('✅ Perfil actualizado como ACTIVO');
            
          } catch (e) {
            debugPrint('❌ Error en actualización forzada manual: $e');
          }
        }
      } else {
        debugPrint('❌ No se pudo obtener ubicación para actualización forzada');
      }
    } catch (e) {
      debugPrint('❌ Error en actualización forzada: $e');
    }
  }

  Future<void> _loadProjects() async {
    try {
      final response = await supabase.from('projects').select();
      setState(() {
        projects = List<Map<String, dynamic>>.from(response);
        if (projects.isNotEmpty) {
          selectedProjectId = null;
          _subscribeToPositions();
        } else {
          selectedProjectId = null;
          _subscribeToPositions();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proyectos: $e')),
        );
      }
    }
  }

  void _cancelAllSubscriptions() {
    _positionsSubscription?.cancel();
    _userLocationsSubscription?.cancel();
    _userProfilesSubscription?.cancel();
    _positionsSubscription = null;
    _userLocationsSubscription = null;
    _userProfilesSubscription = null;
    print('Canceladas todas las suscripciones');
  }

  void _clearProjectData() {
    setState(() {
      devicePositions.clear();
      positionData.clear();
      area = 0;
    });
    print('Datos del proyecto limpiados - Puntos: ${devicePositions.length}');
  }

  void _subscribeToPositions() {

    _cancelAllSubscriptions();
    

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      
      try {
        if (selectedProjectId == null) {
          _subscribeToAllDevices();
          return;
        }

        print('Suscribiéndose a posiciones del proyecto: $selectedProjectId');
        _positionsSubscription = supabase
            .from('positions')
            .stream(primaryKey: ['id'])
            .eq('project_id', int.parse(selectedProjectId!))
            .listen((data) {
              if (mounted) {
                print('Recibidos ${data.length} puntos del proyecto $selectedProjectId');
                

                final filteredData = data.where((position) {
                  final positionProjectId = position['project_id']?.toString();
                  return positionProjectId == selectedProjectId &&
                         position['latitude'] != null &&
                         position['longitude'] != null;
                }).toList();
                
                print('Después del filtro: ${filteredData.length} puntos válidos');
                
                setState(() {
                  devicePositions = filteredData
                      .map(
                        (position) => LatLng(
                          (position['latitude'] as num).toDouble(),
                          (position['longitude'] as num).toDouble(),
                        ),
                      )
                      .toList();
                  positionData = List<Map<String, dynamic>>.from(filteredData);
                });
                _calculateArea();
              }
            }, onError: (error) {
              print('Error en suscripción de posiciones: $error');
            });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al suscribirse a posiciones: $e')),
          );
        }
      }
    });
  }

  void _subscribeToAllDevices() {
    try {
      print('🔄 Suscribiéndose a todas las ubicaciones de usuarios con actualización cada 30s');
      

      void _loadAllUserLocations() async {
        try {
          final currentTime = DateTime.now();
          print('📡 [${currentTime.toString().substring(11, 19)}] Cargando ubicaciones de usuarios...');
          

          final usersResponse = await supabase
              .from('user_profiles')
              .select('*');
          

          final locationsResponse = await supabase
              .from('user_locations')
              .select('*')
              .order('updated_at', ascending: false);
          
          if (mounted) {

            final Map<String, Map<String, dynamic>> locationsByUserId = {};
            for (final location in locationsResponse) {
              final userId = location['user_id'];
              if (!locationsByUserId.containsKey(userId)) {
                locationsByUserId[userId] = location;
              }
            }
            
            final List<Map<String, dynamic>> combinedData = [];
            final List<LatLng> positions = [];
            int onlineCount = 0;
            int totalUsersWithLocation = 0;
            
            for (final user in usersResponse) {
              final userId = user['id'];
              final location = locationsByUserId[userId];
              
              if (location != null && 
                  location['latitude'] != null && 
                  location['longitude'] != null) {
                
                totalUsersWithLocation++;
                
                bool isUserActive = user['is_online'] == true;
                if (isUserActive) onlineCount++;
                
                positions.add(LatLng(
                  (location['latitude'] as num).toDouble(),
                  (location['longitude'] as num).toDouble(),
                ));

                combinedData.add({
                  ...location,
                  'username': user['username'] ?? 'Usuario',
                  'email': user['email'] ?? '',
                  'is_online': isUserActive, 
                  'user_id': userId,
                  'timestamp': location['updated_at'],
                });
              }
            }
            
            print('📍 [${currentTime.toString().substring(11, 19)}] Encontradas ${positions.length} ubicaciones');
            print('👥 Activos: $onlineCount');
            print('📱 Inactivos: ${totalUsersWithLocation - onlineCount}');
            print('📊 Total usuarios con ubicación: $totalUsersWithLocation');
            
            setState(() {
              devicePositions = positions;
              positionData = combinedData;
              allUsers = List<Map<String, dynamic>>.from(usersResponse);
              onlineUsers = List<Map<String, dynamic>>.from(
                usersResponse.where((user) {
                  final userId = user['id'];
                  final userData = combinedData.firstWhere(
                    (data) => data['user_id'] == userId,
                    orElse: () => {'is_online': false},
                  );
                  return userData['is_online'] == true;
                }),
              );
              _lastUpdateTime = currentTime; 
            });
          }
        } catch (e) {
          print('❌ Error cargando ubicaciones: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error actualizando ubicaciones: $e'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
      
      _loadAllUserLocations();
    

      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted && selectedProjectId == null) {
          print('⏰ Timer: Actualización automática de ubicaciones (cada 30s)');
          _loadAllUserLocations();
        } else {
          print('⏰ Timer cancelado: mounted=$mounted, selectedProjectId=$selectedProjectId');
          timer.cancel();
        }
      });

      _userLocationsSubscription = supabase
          .from('user_locations')
          .stream(primaryKey: ['user_id'])
          .listen((data) {
        if (mounted && selectedProjectId == null) {
          print('🔔 Cambio en tiempo real detectado - Recargando ubicaciones');
          _loadAllUserLocations(); 
        }
      }, onError: (error) {
        print('❌ Error en suscripción de ubicaciones: $error');
      });

      _userProfilesSubscription = supabase
          .from('user_profiles')
          .stream(primaryKey: ['id'])
          .listen((users) {
        if (mounted && selectedProjectId == null) {
          print('🔔 Cambio en perfiles detectado - Recargando ubicaciones');
          _loadAllUserLocations(); 
        }
      }, onError: (error) {
        print('❌ Error en suscripción de perfiles: $error');
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al suscribirse a dispositivos: $e')),
        );
      }
    }
  }

  void _calculateArea() {
    print('Calculando área - Puntos disponibles: ${devicePositions.length}');
    if (devicePositions.length >= 3) {
      double calculatedArea = _calculatePolygonArea(devicePositions);
      setState(() {
        area = calculatedArea;
      });
      print('Área calculada: ${area.toStringAsFixed(2)} m²');
    } else {
      setState(() {
        area = 0;
      });
      print('Menos de 3 puntos, área = 0');
    }
  }

  double _calculatePolygonArea(List<LatLng> positions) {
    if (positions.length < 3) return 0;

    double area = 0;
    int n = positions.length;

    for (int i = 0; i < n; i++) {
      int j = (i + 1) % n;
      area += positions[i].longitude * positions[j].latitude;
      area -= positions[j].longitude * positions[i].latitude;
    }

    area = area.abs() / 2.0;
    const double earthRadius = 6371000;
    double areaInSquareMeters =
        area * (earthRadius * earthRadius) * (3.14159 / 180) * (3.14159 / 180);

    return areaInSquareMeters;
  }

  void _onMapTap(LatLng position) async {
  
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.info, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Usa el botón "Marcar Punto GPS" para agregar tu ubicación actual',
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _markCurrentLocation() async {
    if (currentUser?['is_online'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Estás INACTIVO - No puedes marcar puntos. Contacta al administrador para activarte.'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    if (selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('Selecciona un proyecto para marcar puntos'),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white),
                SizedBox(width: 8),
                Text('Los servicios de ubicación están deshabilitados'),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Permisos de ubicación denegados'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Permisos de ubicación denegados permanentemente. Ve a Configuración para habilitarlos.',
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 8),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Text('Obteniendo ubicación GPS...'),
            ],
          ),
          duration: Duration(seconds: 15),
        ),
      );

      late Position position;
      try {
        final tempPosition = await locationService.getCurrentPosition();
        
        if (tempPosition == null) {
          throw Exception('No se pudo obtener la ubicación GPS');
        }
        
        position = tempPosition;

        print(
          '📍 Ubicación obtenida: ${position.latitude}, ${position.longitude}, precisión: ${position.accuracy}m',
        );
      } catch (e) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error obteniendo ubicación: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        print('Error obteniendo ubicación: $e');
        return;
      }

      try {
        await supabase.from('positions').insert({
          'project_id': selectedProjectId != null
              ? int.parse(selectedProjectId!)
              : null,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'altitude': position.altitude,
          'created_by': supabase.auth.currentUser?.id,
          'timestamp': DateTime.now().toIso8601String(),
        });

        print('✅ Punto guardado en la base de datos');

        setState(() {
          devicePositions.add(LatLng(position.latitude, position.longitude));
          positionData.add({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'created_by': supabase.auth.currentUser?.id,
            'timestamp': DateTime.now().toIso8601String(),
            'project_id': selectedProjectId != null ? int.parse(selectedProjectId!) : null,
          });
        });

        _calculateArea();

      } catch (e) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error guardando punto: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        print('Error guardando punto: $e');
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Punto GPS marcado exitosamente'),
                ],
              ),
              Text(
                'Precisión: ${position.accuracy.toStringAsFixed(1)}m',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'Coordenadas: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      String errorMessage = 'Error obteniendo ubicación';
      if (e.toString().contains('location')) {
        errorMessage = 'GPS no disponible. Verifica que esté activado.';
      } else if (e.toString().contains('permission')) {
        errorMessage = 'Permisos de ubicación denegados';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _goToCurrentLocation() async {
    print('Centrando en última ubicación guardada');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Centrando en tu ubicación...'),
            ],
          ),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.blue,
        ),
      );
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuario no autenticado');
      }

      print('Usuario: ${user.id}');
      print('Consultando base de datos...');

      final response = await supabase
          .from('user_locations')
          .select('latitude, longitude, updated_at')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      print('Respuesta de user_locations: $response');

      if (response != null && response.isNotEmpty) {
        final latValue = response['latitude'];
        final lngValue = response['longitude'];
        final updatedAtValue = response['updated_at'];
        
        if (latValue == null || lngValue == null || updatedAtValue == null) {
          print('ADVERTENCIA: Datos incompletos en BD: lat=$latValue, lng=$lngValue, updated=$updatedAtValue');
          await _tryGPSLocation();
          return;
        }
        
        double latitude = (latValue as num).toDouble();
        double longitude = (lngValue as num).toDouble();
        String updatedAt = updatedAtValue.toString();
        
        if (latitude.isNaN || longitude.isNaN || (latitude == 0.0 && longitude == 0.0)) {
          print('ADVERTENCIA: Coordenadas inválidas: $latitude, $longitude');
          await _tryGPSLocation();
          return;
        }
        
        DateTime lastUpdate = DateTime.parse(updatedAt);
        Duration timeDiff = DateTime.now().difference(lastUpdate);
        String timeAgo = _formatTimeAgo(timeDiff);

        print('Centrando en: $latitude, $longitude (actualizado $timeAgo)');
        
        _mapController.move(LatLng(latitude, longitude), 16.0);
        
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.my_location, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('📍 Centrado en tu ubicación ($timeAgo)'),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        print('Mapa centrado exitosamente');
      } else {
        print('No hay ubicaciones en BD, intentando con GPS...');
        await _tryGPSLocation();
      }
    } catch (e) {
      print('ERROR: Error al centrar ubicación: $e');
      await _tryGPSLocation();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        String errorMessage;
        if (e.toString().contains('No hay ubicación guardada')) {
          errorMessage = '� Aún no tienes ubicaciones guardadas. Espera un momento para que se registre tu posición.';
        } else {
          errorMessage = 'No se pudo centrar en tu ubicación. Intenta nuevamente.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(errorMessage),
                ),
              ],
            ),
            backgroundColor: Colors.orange[600],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _formatTimeAgo(Duration duration) {
    if (duration.inMinutes < 1) {
      return 'hace ${duration.inSeconds} segundos';
    } else if (duration.inHours < 1) {
      return 'hace ${duration.inMinutes} minutos';
    } else if (duration.inDays < 1) {
      return 'hace ${duration.inHours} horas';
    } else {
      return 'hace ${duration.inDays} días';
    }
  }

  Future<void> _tryGPSLocation() async {
    try {
      print('🛰️ Intentando obtener ubicación GPS como fallback...');
      
      Position? position = await locationService.getCurrentPosition();
      
      if (position != null) {
        print('📍 GPS obtenido: ${position.latitude}, ${position.longitude}');
        _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
        
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.gps_fixed, color: Colors.white),
                  SizedBox(width: 8),
                  Text('📍 Centrado usando GPS actual'),
                ],
              ),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
        print('Centrado con GPS exitoso');
      } else {
        throw Exception('GPS no disponible');
      }
    } catch (e) {
      print('ERROR: Error con GPS fallback: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('📍 No se encontró ubicación. Espera un momento a que se active el GPS.'),
                ),
              ],
            ),
            backgroundColor: Colors.orange[600],
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Reintentar',
              textColor: Colors.white,
              onPressed: () {
                _goToCurrentLocation();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _signOut() async {
    try {
      locationService.dispose();
      await SimpleBackgroundService.stopBackgroundTracking();
      await supabase.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cerrar sesión: $e')));
      }
    }
  }

  void _handleMenuSelection(String value) async {
    switch (value) {
      case 'profile':
        _showProfileDialog();
        break;
      case 'logout':
        await _signOut();
        break;
    }
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Información del Usuario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usuario: ${currentUser?['username'] ?? 'N/A'}'),
            Text('Email: ${currentUser?['email'] ?? 'N/A'}'),
            Text('Rol: ${userRole == 'admin' ? 'Administrador' : 'Usuario'}'),
            Text(
              'Estado: ${currentUser?['is_online'] == true ? 'Activo' : 'Inactivo'}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _navigateToAdmin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminPageImproved()),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[600]!, Colors.blue[800]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 30,
                  child: Text(
                    currentUser?['username']?.substring(0, 1).toUpperCase() ??
                        'U',
                    style: TextStyle(
                      color: Colors.blue[600],
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  currentUser?['username'] ?? 'Usuario',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  userRole == 'admin' ? 'Administrador' : 'Usuario',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Ver Dispositivos'),
            selected: selectedProjectId == null,
            onTap: () {
              print('🔄 Cambiando a "Ver Dispositivos"');
              _clearProjectData();
              setState(() {
                selectedProjectId = null;
              });
              _subscribeToPositions();
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ...projects.map(
            (project) => ListTile(
              leading: const Icon(Icons.folder),
              title: Text(project['name']),
              selected: selectedProjectId == project['id'].toString(),
              onTap: () {
                print('🔄 Cambiando a proyecto: ${project['name']} (ID: ${project['id']})');
                _clearProjectData();
                setState(() {
                  selectedProjectId = project['id'].toString();
                });
                _subscribeToPositions();
                Navigator.pop(context);
              },
            ),
          ),
          const Divider(),
          if (userRole == 'admin')
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Panel de Administrador'),
              onTap: () {
                Navigator.pop(context);
                _navigateToAdmin();
              },
            ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              Navigator.pop(context);
              _signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.blue[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: Colors.blue[200]!)),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String?>(
            value: selectedProjectId,
            decoration: InputDecoration(
              labelText: 'Proyecto',
              prefixIcon: const Icon(Icons.folder),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Row(
                  children: [
                    Icon(Icons.devices, size: 20),
                    SizedBox(width: 8),
                    Text('Ver todos los dispositivos'),
                  ],
                ),
              ),
              ...projects.map(
                (project) => DropdownMenuItem<String?>(
                  value: project['id'].toString(),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, size: 20),
                      const SizedBox(width: 8),
                      Text(project['name']),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              print('🔄 Dropdown - Cambiando proyecto a: $value');
              _clearProjectData();
              setState(() {
                selectedProjectId = value;
              });
              _subscribeToPositions();
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoCard(
                icon: Icons.location_on,
                title: selectedProjectId != null ? 'Puntos' : 'Ubicaciones',
                value: '${devicePositions.length}',
                color: Colors.blue,
              ),
              if (selectedProjectId != null && area > 0)
                _buildInfoCard(
                  icon: Icons.square_foot,
                  title: 'Área',
                  value: '${area.toStringAsFixed(1)} m²',
                  color: Colors.green,
                ),
              if (selectedProjectId == null) ...[
                _buildInfoCard(
                  icon: Icons.people,
                  title: '🟢 Activos',
                  value: '${onlineUsers.length}',
                  color: Colors.green,
                ),
                _buildInfoCard(
                  icon: Icons.people_outline,
                  title: '🔴 Inactivos',
                  value: '${allUsers.length - onlineUsers.length}',
                  color: Colors.red,
                ),
              ],
            ],
          ),
          if (selectedProjectId == null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.update,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Column(
                  children: [
                    Text(
                      'Se actualiza cada 30s',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (_lastUpdateTime != null)
                      Text(
                        'Última actualización: ${_lastUpdateTime!.toString().substring(11, 19)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[800],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    return devicePositions.asMap().entries.map((entry) {
      int index = entry.key;
      LatLng position = entry.value;

      String markerInfo = '';
      Color markerColor = Colors.red;
      IconData markerIcon = Icons.location_pin;

      if (selectedProjectId == null && index < positionData.length) {
        var data = positionData[index];
        
        String username = data['username'] ?? 'Usuario ${index + 1}';
        bool isUserOnline = data['is_online'] == true;
        bool isCurrentUser = data['user_id'] == supabase.auth.currentUser?.id;
        
        String timeInfo = '';
        if (data['timestamp'] != null) {
          try {
            DateTime lastUpdate = DateTime.parse(data['timestamp']);
            Duration timeDiff = DateTime.now().difference(lastUpdate);
            timeInfo = _formatTimeAgo(timeDiff);
          } catch (e) {
            timeInfo = 'Tiempo desconocido';
          }
        }

        if (isCurrentUser) {
          markerColor = Colors.green;
          markerIcon = Icons.my_location;
          markerInfo = '📍 TÚ ($username)${timeInfo.isNotEmpty ? ' - $timeInfo' : ''}';
        } else if (isUserOnline) {
          markerColor = Colors.blue;
          markerIcon = Icons.person_pin_circle;
          markerInfo = '🟢 ACTIVO: $username${timeInfo.isNotEmpty ? ' - $timeInfo' : ''}';
        } else {
          markerColor = Colors.red;
          markerIcon = Icons.location_off;
          markerInfo = '🔴 INACTIVO: $username${timeInfo.isNotEmpty ? ' - Última vez $timeInfo' : ''}';
        }
      } else {
        markerInfo = '📌 PUNTO ${index + 1}';
        markerColor = Colors.purple;
        markerIcon = Icons.push_pin;
      }

      return Marker(
        point: position,
        child: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(markerIcon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            markerInfo,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (selectedProjectId == null && index < positionData.length) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Lat: ${position.latitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Lng: ${position.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (positionData[index]['accuracy'] != null)
                        Text(
                          'Precisión: ±${positionData[index]['accuracy'].toStringAsFixed(1)}m',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ],
                ),
                duration: const Duration(seconds: 4),
                backgroundColor: markerColor,
              ),
            );
          },
          child: Container(
            width: 40,
            height: 40, 
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: markerColor, width: 3),
              boxShadow: [
                BoxShadow(
                  color: markerColor.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Icon(markerIcon, color: markerColor, size: 24),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildFloatingActionButtons() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (selectedProjectId != null) ...[
          FloatingActionButton.extended(
            heroTag: "mark_gps",
            backgroundColor: currentUser?['is_online'] == true ? Colors.green[600] : Colors.red[600],
            onPressed: _markCurrentLocation,
            icon: const Icon(Icons.gps_fixed, color: Colors.white),
            label: const Text(
              'Marcar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            tooltip: currentUser?['is_online'] == true 
                ? 'Marcar punto en tu ubicación actual'
                : 'No puedes marcar puntos - Estás inactivo',
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          heroTag: "location",
          mini: true,
          backgroundColor: Colors.blue[600],
          onPressed: _goToCurrentLocation,
          child: const Icon(Icons.my_location, color: Colors.white),
          tooltip: 'Centrar en mi última ubicación',
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: "zoom_out",
          mini: true,
          backgroundColor: Colors.grey[600],
          onPressed: () => _mapController.move(
            _mapController.camera.center,
            _mapController.camera.zoom - 1,
          ),
          child: const Icon(Icons.remove, color: Colors.white),
          tooltip: 'Alejar',
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: "zoom_in",
          backgroundColor: Colors.grey[600],
          onPressed: () => _mapController.move(
            _mapController.camera.center,
            _mapController.camera.zoom + 1,
          ),
          child: const Icon(Icons.add, color: Colors.white),
          tooltip: 'Acercar',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          selectedProjectId == null
              ? 'Dispositivos Conectados'
              : 'Proyecto ${projects.firstWhere((p) => p['id'].toString() == selectedProjectId, orElse: () => {'name': 'Desconocido'})['name']}',
        ),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[600]!, Colors.blue[800]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (selectedProjectId == null) 
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar ubicaciones manualmente',
              onPressed: () async {
                print('🔄 Actualización manual solicitada');
                if (selectedProjectId == null) {
                  await _forceLocationUpdate();
                  
                  _subscribeToAllDevices();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.refresh, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Actualizando ubicaciones...'),
                        ],
                      ),
                      duration: Duration(seconds: 2),
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              },
            ),
          PopupMenuButton<String>(
            icon: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                currentUser?['username']?.substring(0, 1).toUpperCase() ?? 'U',
                style: TextStyle(
                  color: Colors.blue[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onSelected: _handleMenuSelection,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person),
                    const SizedBox(width: 8),
                    Text(currentUser?['username'] ?? 'Usuario'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'role',
                child: Row(
                  children: [
                    Icon(
                      userRole == 'admin'
                          ? Icons.admin_panel_settings
                          : Icons.person,
                    ),
                    const SizedBox(width: 8),
                    Text(userRole == 'admin' ? 'Administrador' : 'Usuario'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildInfoPanel(),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(-0.22985, -78.52495),
                initialZoom: 13.0,
                minZoom: 5.0,
                maxZoom: 18.0,
                onTap: (tapPosition, point) => _onMapTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.tracking_app',
                ),
                MarkerLayer(markers: _buildMarkers()),
                if (devicePositions.length > 2 && selectedProjectId != null)
                  PolygonLayer(
                    polygons: [

                      Polygon(
                        points: devicePositions,
                        borderStrokeWidth: 0,
                        borderColor: Colors.transparent,
                        color: Colors.orange.withOpacity(0.2),
                      ),

                      Polygon(
                        points: devicePositions,
                        borderStrokeWidth: 4.0,
                        borderColor: Colors.orange[700]!,
                        color: Colors.orange.withOpacity(0.5),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
