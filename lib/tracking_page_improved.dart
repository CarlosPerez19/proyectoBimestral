import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'services/location_service.dart';
import 'admin_page_improved.dart';

class TrackingPageImproved extends StatefulWidget {
  const TrackingPageImproved({super.key});

  @override
  State<TrackingPageImproved> createState() => _TrackingPageImprovedState();
}

class _TrackingPageImprovedState extends State<TrackingPageImproved> {
  final supabase = Supabase.instance.client;
  final locationService = LocationService();
  List<LatLng> devicePositions = [];
  List<Map<String, dynamic>> positionData = [];
  List<Map<String, dynamic>> onlineUsers = [];
  List<Map<String, dynamic>> allUsers = []; // Nueva lista para todos los usuarios
  double area = 0;
  List<Map<String, dynamic>> projects = [];
  String? selectedProjectId;
  String? userRole;
  Map<String, dynamic>? currentUser;
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Variables para manejar las suscripciones
  StreamSubscription? _positionsSubscription;
  StreamSubscription? _userLocationsSubscription;
  StreamSubscription? _userProfilesSubscription;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadProjects();
    _startLocationService();
  }

  @override
  void dispose() {
    // Cancelar todas las suscripciones activas
    _positionsSubscription?.cancel();
    _userLocationsSubscription?.cancel();
    _userProfilesSubscription?.cancel();
    locationService.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Cargar perfil básico
        final profile = await supabase
            .from('user_profiles')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();

        // Cargar rol por separado
        final roleData = await supabase
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id)
            .maybeSingle();

        if (profile != null) {
          setState(() {
            currentUser = {...profile, 'role': roleData?['role'] ?? 'user'};
            userRole = roleData?['role'] ?? 'user';
          });
        } else {
          // Crear perfil si no existe
          await supabase.from('user_profiles').upsert({
            'id': user.id,
            'email': user.email,
            'username': user.email?.split('@')[0] ?? 'Usuario',
            'is_online': false,
          });

          await supabase.from('user_roles').upsert({
            'user_id': user.id,
            'role': 'user',
          });

          setState(() {
            currentUser = {
              'id': user.id,
              'email': user.email,
              'username': user.email?.split('@')[0] ?? 'Usuario',
              'role': 'user',
            };
            userRole = 'user';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  Future<void> _startLocationService() async {
    try {
      await locationService.startLocationTracking();
    } catch (e) {
      debugPrint('LocationService error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS no disponible, funcionando sin ubicación'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
    print('🔄 Canceladas todas las suscripciones');
  }

  void _clearProjectData() {
    setState(() {
      devicePositions.clear();
      positionData.clear();
      area = 0;
    });
    print('🧹 Datos del proyecto limpiados - Puntos: ${devicePositions.length}');
  }

  void _subscribeToPositions() {
    // Cancelar suscripciones anteriores
    _cancelAllSubscriptions();
    
    // Esperar un momento para asegurar que las suscripciones se cancelen
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      
      try {
        if (selectedProjectId == null) {
          _subscribeToAllDevices();
          return;
        }

        print('🔄 Suscribiéndose a posiciones del proyecto: $selectedProjectId');
        _positionsSubscription = supabase
            .from('positions')
            .stream(primaryKey: ['id'])
            .eq('project_id', int.parse(selectedProjectId!))
            .listen((data) {
              if (mounted) {
                print('📍 Recibidos ${data.length} puntos del proyecto $selectedProjectId');
                
                // Verificar que los datos pertenecen al proyecto correcto
                final filteredData = data.where((position) {
                  final positionProjectId = position['project_id']?.toString();
                  return positionProjectId == selectedProjectId &&
                         position['latitude'] != null &&
                         position['longitude'] != null;
                }).toList();
                
                print('📍 Después del filtro: ${filteredData.length} puntos válidos');
                
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
              print('❌ Error en suscripción de posiciones: $error');
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
      print('🔄 Suscribiéndose a todas las ubicaciones de usuarios');
      _userLocationsSubscription = supabase.from('user_locations').stream(primaryKey: ['user_id']).listen((
        data,
      ) {
        if (mounted) {
          print('📍 Recibidas ${data.length} ubicaciones de usuarios');
          setState(() {
            devicePositions = data
                .where(
                  (location) =>
                      location['latitude'] != null &&
                      location['longitude'] != null,
                )
                .map(
                  (location) => LatLng(
                    (location['latitude'] as num).toDouble(),
                    (location['longitude'] as num).toDouble(),
                  ),
                )
                .toList();
            positionData = List<Map<String, dynamic>>.from(data);
          });
        }
      }, onError: (error) {
        print('❌ Error en suscripción de ubicaciones: $error');
      });

      // Obtener información de todos los usuarios
      _userProfilesSubscription = supabase.from('user_profiles').stream(primaryKey: ['id']).listen((users) {
        if (mounted) {
          setState(() {
            allUsers = List<Map<String, dynamic>>.from(users); // Todos los usuarios
            onlineUsers = List<Map<String, dynamic>>.from(
              users.where((user) => user['is_online'] == true),
            );
          });
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
    print('📐 Calculando área - Puntos disponibles: ${devicePositions.length}');
    if (devicePositions.length >= 3) {
      double calculatedArea = _calculatePolygonArea(devicePositions);
      setState(() {
        area = calculatedArea;
      });
      print('📐 Área calculada: ${area.toStringAsFixed(2)} m²');
    } else {
      setState(() {
        area = 0;
      });
      print('📐 Menos de 3 puntos, área = 0');
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
    // Los puntos ya no se agregan tocando el mapa
    // Se muestran instrucciones al usuario
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
    // Verificar si el usuario está activo/en línea
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
      // Verificar permisos de ubicación antes de continuar
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

      // Mostrar indicador de carga
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

      // Obtener ubicación actual con alta precisión
      Position position;
      try {
        position =
            await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.bestForNavigation,
              timeLimit: const Duration(seconds: 15), // Más tiempo para Windows
            ).timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                throw Exception('Timeout obteniendo ubicación GPS');
              },
            );

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
        print('❌ Error obteniendo ubicación: $e');
        return;
      }

      // Guardar el punto en la base de datos
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

        // Agregar el punto localmente al mapa inmediatamente
        setState(() {
          devicePositions.add(LatLng(position.latitude, position.longitude));
          positionData.add({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'created_by': supabase.auth.currentUser?.id,
            'timestamp': DateTime.now().toIso8601String(),
          });
        });
      } catch (e) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error guardando punto: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        print('❌ Error guardando punto: $e');
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Mostrar confirmación con información del punto
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

      // Centrar el mapa en la nueva ubicación
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
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener ubicación: $e')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    try {
      locationService.dispose();
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
              'Estado: ${currentUser?['is_online'] == true ? 'En línea' : 'Fuera de línea'}',
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
                title: 'Puntos',
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
              if (selectedProjectId == null)
                _buildInfoCard(
                  icon: Icons.people,
                  title: 'En línea',
                  value: '${onlineUsers.length}',
                  color: Colors.orange,
                ),
            ],
          ),
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
        var userInfo = onlineUsers.firstWhere(
          (user) => user['id'] == data['user_id'],
          orElse: () => {},
        );
        
        // Buscar información del usuario en la lista completa si no está en línea
        var fullUserInfo = allUsers.firstWhere(
          (user) => user['id'] == data['user_id'],
          orElse: () => {},
        );

        bool isCurrentUser = data['user_id'] == supabase.auth.currentUser?.id;
        bool isUserOnline = userInfo.isNotEmpty;

        if (isCurrentUser) {
          markerColor = Colors.green;
          markerInfo = 'Tú (${fullUserInfo['username'] ?? userInfo['username'] ?? 'Usuario'})';
        } else if (isUserOnline) {
          markerColor = Colors.blue;
          markerInfo = '${userInfo['username'] ?? 'Usuario'}';
        } else {
          // Usuario inactivo - color rojo
          markerColor = Colors.red;
          String username = fullUserInfo['username'] ?? 'Usuario ${index + 1}';
          markerInfo = 'Inactivo - $username';
        }

        markerIcon = isUserOnline
            ? Icons.person_pin
            : Icons.phone_android;
      } else {
        markerInfo = 'PUNTO ${index + 1}';
        markerColor = Colors.blue;
        markerIcon = Icons.location_pin;
      }

      return Marker(
        point: position,
        child: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(markerIcon, color: Colors.white, size: 60),
                    const SizedBox(width: 50),
                    Text(markerInfo),
                  ],
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: markerColor,
              ),
            );
          },
          child: Container(
            width: 120,
            height: 120, 
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(markerIcon, color: markerColor, size: 30),
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
          tooltip: 'Centrar en mi ubicación',
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
                      // Sombra del polígono (capa inferior)
                      Polygon(
                        points: devicePositions,
                        borderStrokeWidth: 0,
                        borderColor: Colors.transparent,
                        color: Colors.orange.withOpacity(0.2),
                      ),
                      // Polígono principal (capa superior)
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
