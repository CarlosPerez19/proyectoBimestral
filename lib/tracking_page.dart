import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final supabase = Supabase.instance.client;
  List<LatLng> devicePositions = [];
  double area = 0;
  List<Map<String, dynamic>> projects = [];
  int? selectedProjectId;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final response = await supabase.from('projects').select();
    setState(() {
      projects = List<Map<String, dynamic>>.from(response);
      if (projects.isNotEmpty) {
        selectedProjectId = projects.first['id'];
        _subscribeToPositions();
      } else {
        selectedProjectId = null;
        devicePositions = [];
        area = 0;
      }
    });
  }

  void _subscribeToPositions() {
    if (selectedProjectId == null) {
      setState(() {
        devicePositions = [];
        area = 0;
      });
      return;
    }
    supabase
        .from('positions')
        .stream(primaryKey: ['id'])
        .eq('project_id', selectedProjectId as Object)
        .listen((data) {
      setState(() {
        devicePositions = data
            .map<LatLng>((row) => LatLng(row['latitude'], row['longitude']))
            .toList();
        area = _calculatePolygonArea(devicePositions);
      });
    });
  }

  Future<void> _takeLocation() async {
    final position = await Geolocator.getCurrentPosition();
    if (selectedProjectId == null) return;
    await supabase.from('positions').insert({
      'project_id': selectedProjectId,
      'device_id': supabase.auth.currentUser?.id ?? 'unknown',
      'latitude': position.latitude,
      'longitude': position.longitude,
    });
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Proyecto'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre del proyecto'),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await supabase
                    .from('projects')
                    .insert({'name': controller.text}).select();
                Navigator.of(ctx).pop();
                await _loadProjects();
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  double _calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0;
    double area = 0;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      area += (points[j].longitude + points[i].longitude) *
              (points[j].latitude - points[i].latitude);
      j = i;
    }
    return area.abs() / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking en Tiempo Real'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    value: selectedProjectId,
                    hint: const Text('Selecciona un proyecto'),
                    items: projects
                        .map((proj) => DropdownMenuItem<int>(
                              value: proj['id'],
                              child: Text(proj['name']),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedProjectId = value;
                        devicePositions = [];
                        area = 0;
                        _subscribeToPositions();
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _createProject,
                  tooltip: 'Crear nuevo proyecto',
                ),
                IconButton(
                  icon: const Icon(Icons.my_location),
                  onPressed: _takeLocation,
                  tooltip: 'Tomar ubicación',
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                center: devicePositions.isNotEmpty
                    ? devicePositions[0]
                    : LatLng(0, 0),
                zoom: 16,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app',
                ),
                MarkerLayer(
                  markers: devicePositions
                      .map((pos) => Marker(
                            point: pos,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.circle,
                                  color: Colors.red,
                                  size: 38,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                if (devicePositions.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: devicePositions,
                        color: Colors.orange.withOpacity(0.2),
                        borderStrokeWidth: 0,
                        borderColor: Colors.transparent,
                      ),
                      Polygon(
                        points: devicePositions,
                        color: Colors.orange.withOpacity(0.5),
                        borderStrokeWidth: 4,
                        borderColor: Colors.orange[700]!,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Área del terreno: ${area.toStringAsFixed(2)} unidades',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}