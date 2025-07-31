import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'tracking_page_improved.dart';
import 'main.dart'; // Para AuthGate

class AdminPageImproved extends StatefulWidget {
  const AdminPageImproved({super.key});

  @override
  State<AdminPageImproved> createState() => _AdminPageImprovedState();
}

class _AdminPageImprovedState extends State<AdminPageImproved> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> onlineUsers = [];
  List<Map<String, dynamic>> projects = [];
  bool isLoading = true;
  
  // Timer para actualizar ubicaciones cada 30 segundos
  Timer? _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _startLocationUpdateTimer(); // Iniciar timer automático
  }

  @override
  void dispose() {
    _tabController.dispose();
    _locationUpdateTimer?.cancel(); // Cancelar timer al salir
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadUsers(),
      _loadOnlineUsers(),
      _loadProjects(),
    ]);
  }

  // Método para iniciar el timer de actualización automática cada 30 segundos
  void _startLocationUpdateTimer() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      print('🔄 AdminPage: Actualizando ubicaciones automáticamente');
      await _loadOnlineUsers(); // Recargar usuarios online cada 30 segundos
      if (mounted) {
        setState(() {}); // Forzar actualización de la UI
      }
    });
    print('⏰ AdminPage: Timer de actualización iniciado (30 segundos)');
  }

  Future<void> _loadUsers() async {
    try {
      // Cargar perfiles
      final profiles = await supabase
          .from('user_profiles')
          .select('*');
      
      // Cargar roles
      final roles = await supabase
          .from('user_roles')
          .select('*');
      
      // Combinar datos manualmente de forma simple
      final combinedUsers = <Map<String, dynamic>>[];
      
      for (final profile in profiles) {
        final userRole = roles.firstWhere(
          (role) => role['user_id'] == profile['id'],
          orElse: () => {'role': 'user'},
        );
        
        combinedUsers.add({
          'id': profile['id'],
          'email': profile['email'],
          'username': profile['username'],
          'is_online': profile['is_online'],
          'role': userRole['role'],
        });
      }
      
      setState(() {
        users = combinedUsers;
        isLoading = false;
      });
    } catch (e) {
      print('Error cargando usuarios: $e');
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando usuarios: $e')),
        );
      }
    }
  }

  Future<void> _loadOnlineUsers() async {
    try {
      print('🔄 AdminPage: Cargando usuarios online...');
      // Obtener ubicaciones activas con información del usuario
      final locations = await supabase
          .from('user_locations')
          .select('*, user_profiles!inner(*)')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);

      // Cargar roles para los usuarios online
      final userIds = locations.map((loc) => loc['user_id']).toList();
      final roles = userIds.isNotEmpty 
          ? await supabase
              .from('user_roles')
              .select('*')
              .filter('user_id', 'in', '(${userIds.map((id) => "'$id'").join(',')})')
          : <Map<String, dynamic>>[];

      // Combinar datos de ubicación, perfil y rol
      final combinedData = locations.map((location) {
        final userRole = roles.firstWhere(
          (role) => role['user_id'] == location['user_id'],
          orElse: () => {'role': 'user'},
        );
        
        return {
          ...location,
          'user_profiles': {
            ...location['user_profiles'],
            'role': userRole['role'],
          },
        };
      }).toList();

      if (mounted) {
        setState(() {
          onlineUsers = combinedData;
        });
        print('✅ AdminPage: ${combinedData.length} usuarios online actualizados - ${DateTime.now().toString().substring(11, 19)}');
      }
    } catch (e) {
      print('❌ AdminPage: Error cargando usuarios online: $e');
      if (mounted) {
        setState(() {
          onlineUsers = [];
        });
      }
    }
  }

  Future<void> _loadProjects() async {
    try {
      final response = await supabase
          .from('projects')
          .select('*')
          .order('created_at', ascending: false);
      
      setState(() {
        projects = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando proyectos: $e')),
        );
      }
    }
  }

  Future<void> _createUser() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final usernameController = TextEditingController();
    String selectedRole = 'user';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add, color: Colors.blue),
              SizedBox(width: 8),
              Text('Crear Nuevo Usuario'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de usuario',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Rol del Usuario',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      RadioListTile<String>(
                        title: const Text('Usuario Normal'),
                        subtitle: const Text('Acceso básico al sistema'),
                        value: 'user',
                        groupValue: selectedRole,
                        onChanged: (value) {
                          setDialogState(() => selectedRole = value!);
                        },
                      ),
                      RadioListTile<String>(
                        title: const Text('Administrador'),
                        subtitle: const Text('Acceso completo al sistema'),
                        value: 'admin',
                        groupValue: selectedRole,
                        onChanged: (value) {
                          setDialogState(() => selectedRole = value!);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (emailController.text.isNotEmpty && 
                    passwordController.text.isNotEmpty &&
                    usernameController.text.isNotEmpty) {
                  try {
                    // Crear usuario con Supabase Auth
                    final response = await supabase.auth.signUp(
                      email: emailController.text.trim(),
                      password: passwordController.text,
                      data: {
                        'username': usernameController.text.trim(),
                        'role': selectedRole,
                      },
                    );

                    if (response.user != null) {
                      // Crear perfil sin role (va en tabla separada)
                      await supabase.from('user_profiles').upsert({
                        'id': response.user!.id,
                        'email': emailController.text.trim(),
                        'username': usernameController.text.trim(),
                        'is_online': true,
                      });

                      // Crear rol en tabla separada
                      await supabase.from('user_roles').upsert({
                        'user_id': response.user!.id,
                        'role': selectedRole,
                      });

                      Navigator.pop(ctx);
                      _loadUsers();
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Usuario ${usernameController.text} creado como $selectedRole'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error creando usuario: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_open, color: Colors.blue),
            SizedBox(width: 8),
            Text('Crear Nuevo Proyecto'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del proyecto',
                prefixIcon: Icon(Icons.label),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                try {
                  await supabase.from('projects').insert({
                    'name': nameController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'created_by': supabase.auth.currentUser?.id,
                  });

                  Navigator.pop(ctx);
                  _loadProjects();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Proyecto "${nameController.text}" creado'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error creando proyecto: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeUserStatus(Map<String, dynamic> user) async {
    bool newStatus = !(user['is_online'] ?? false);
    
    try {
      await supabase
          .from('user_profiles')
          .update({'is_online': newStatus})
          .eq('id', user['id']);
      
      _loadUsers();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['username']} ${newStatus ? 'activado' : 'desactivado'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cambiando estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _changeUserRole(Map<String, dynamic> user) async {
    String newRole = user['role'] == 'admin' ? 'user' : 'admin';
    
    try {
      // Actualizar en la tabla user_roles en lugar de user_profiles
      await supabase
          .from('user_roles')
          .update({'role': newRole})
          .eq('user_id', user['id']);
      
      _loadUsers();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['username']} ahora es $newRole'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cambiando rol: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de eliminar a ${user['username']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('user_profiles')
            .delete()
            .eq('id', user['id']);
        
        _loadUsers();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Usuario ${user['username']} eliminado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando usuario: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildDashboardTab() {
    int totalUsers = users.length;
    int activeUsers = users.where((user) => user['is_online'] ?? false).length;
    int adminUsers = users.where((user) => user['role'] == 'admin').length;
    int regularUsers = users.where((user) => user['role'] == 'user').length;
    int totalProjects = projects.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del Sistema',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 20),
          
          // Tarjetas de estadísticas
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.2,
            children: [
              _buildStatCard(
                'Total Usuarios',
                totalUsers.toString(),
                Icons.people,
                Colors.blue,
              ),
              _buildStatCard(
                'Usuarios Activos',
                activeUsers.toString(),
                Icons.online_prediction,
                Colors.green,
              ),
              _buildStatCard(
                'Administradores',
                adminUsers.toString(),
                Icons.admin_panel_settings,
                Colors.red,
              ),
              _buildStatCard(
                'Topógrafos',
                regularUsers.toString(),
                Icons.engineering,
                Colors.orange,
              ),
              _buildStatCard(
                'Total Proyectos',
                totalProjects.toString(),
                Icons.folder,
                Colors.purple,
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Dispositivos conectados en tiempo real
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Dispositivos Conectados: ${onlineUsers.length}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'EN VIVO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (onlineUsers.isEmpty)
                    const Center(
                      child: Column(
                        children: [
                          Icon(Icons.location_off, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'No hay dispositivos conectados',
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Se actualiza automáticamente cada 30 segundos',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: onlineUsers.take(5).map((user) {
                        final username = user['user_profiles']?['username'] ?? 'Usuario';
                        final coords = '${user['latitude'].toStringAsFixed(6)}, ${user['longitude'].toStringAsFixed(6)}';
                        final accuracy = user['accuracy']?.toStringAsFixed(1) ?? 'N/A';
                        final lastSeen = user['last_seen'] != null 
                            ? DateTime.parse(user['last_seen']).toLocal().toString().substring(11, 19)
                            : 'N/A';
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[100],
                            child: const Icon(Icons.person_pin_circle, color: Colors.green),
                          ),
                          title: Text(username),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('📍 $coords'),
                              Text('🎯 Precisión: ${accuracy}m • 🕒 $lastSeen'),
                            ],
                          ),
                          trailing: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          isThreeLine: true,
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
         
          const SizedBox(height: 24),
         
          // Proyectos recientes
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder_open, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Proyectos Recientes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (projects.isEmpty)
                    const Text('No hay proyectos creados')
                  else
                    ...projects.take(3).map((project) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.purple[100],
                        child: const Icon(Icons.folder, color: Colors.purple),
                      ),
                      title: Text(project['name'] ?? 'Proyecto sin nombre'),
                      subtitle: Text(
                        'Creado: ${_formatDateTime(project['created_at'])}',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'Desconocido';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Hace unos segundos';
      } else if (difference.inMinutes < 60) {
        return 'Hace ${difference.inMinutes} min';
      } else if (difference.inHours < 24) {
        return 'Hace ${difference.inHours} horas';
      } else {
        return 'Hace ${difference.inDays} días';
      }
    } catch (e) {
      return 'Fecha inválida';
    }
  }

  Widget _buildUsersTab() {
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total de usuarios: ${users.length}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _createUser,
                  icon: const Icon(Icons.add),
                  label: const Text('Crear Usuario'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: user['role'] == 'admin' ? Colors.red[100] : Colors.blue[100],
                      child: Icon(
                        user['role'] == 'admin' ? Icons.admin_panel_settings : Icons.person,
                        color: user['role'] == 'admin' ? Colors.red : Colors.blue,
                      ),
                    ),
                    title: Text(
                      user['username'] ?? 'Sin nombre',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user['email'] ?? 'Sin email'),
                        Row(
                          children: [
                            Text(
                              'Rol: ${user['role'] == 'admin' ? 'Administrador' : 'Topógrafo'}',
                              style: TextStyle(
                                color: user['role'] == 'admin' ? Colors.red : Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (user['is_online'] ?? false) ? Colors.green : Colors.grey,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (user['is_online'] ?? false) ? 'ACTIVO' : 'INACTIVO',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'role',
                          child: Row(
                            children: [
                              const Icon(Icons.swap_horiz),
                              const SizedBox(width: 8),
                              Text('Cambiar a ${user['role'] == 'admin' ? 'Topógrafo' : 'Admin'}'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'status',
                          child: Row(
                            children: [
                              Icon(
                                (user['is_online'] ?? false) ? Icons.block : Icons.check_circle,
                                color: (user['is_online'] ?? false) ? Colors.orange : Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                (user['is_online'] ?? false) ? 'Desactivar' : 'Activar',
                                style: TextStyle(
                                  color: (user['is_online'] ?? false) ? Colors.orange : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_forever, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Eliminar', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'role') {
                          _changeUserRole(user);
                        } else if (value == 'status') {
                          _changeUserStatus(user);
                        } else if (value == 'delete') {
                          _deleteUser(user);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectsTab() {
    return RefreshIndicator(
      onRefresh: _loadProjects,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total de proyectos: ${projects.length}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _createProject,
                  icon: const Icon(Icons.add),
                  label: const Text('Crear Proyecto'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.folder, color: Colors.white),
                    ),
                    title: Text(
                      project['name'] ?? 'Sin nombre',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(project['description'] ?? 'Sin descripción'),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Eliminar', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteProject(project);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProject(Map<String, dynamic> project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de eliminar el proyecto "${project['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('projects')
            .delete()
            .eq('id', project['id']);
        
        _loadProjects();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Proyecto "${project['name']}" eliminado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando proyecto: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cerrando sesión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 30,
                  child: Icon(
                    Icons.admin_panel_settings,
                    color: Colors.blue,
                    size: 35,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Panel de Administrador',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Gestión del Sistema',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Ir a Topografía'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const TrackingPageImproved(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            selected: _tabController.index == 0,
            onTap: () {
              _tabController.animateTo(0);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Usuarios'),
            selected: _tabController.index == 1,
            onTap: () {
              _tabController.animateTo(1);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Proyectos'),
            selected: _tabController.index == 2,
            onTap: () {
              _tabController.animateTo(2);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administrador'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[600]!, Colors.blue[800]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.people), text: 'Usuarios'),
            Tab(icon: Icon(Icons.folder), text: 'Proyectos'),
          ],
        ),
      ),
      drawer: _buildDrawer(),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDashboardTab(),
                _buildUsersTab(),
                _buildProjectsTab(),
              ],
            ),
    );
  }
}
