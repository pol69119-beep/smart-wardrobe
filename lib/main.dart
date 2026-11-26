import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SmartWardrobeApp());
}

class SmartWardrobeApp extends StatefulWidget {
  const SmartWardrobeApp({super.key});

  @override
  State<SmartWardrobeApp> createState() => _SmartWardrobeAppState();
}

class _SmartWardrobeAppState extends State<SmartWardrobeApp> {
  int _selectedIndex = 0;
  late PageController _pageController;

  static const List<Widget> _widgetOptions = <Widget>[
    GarmentsGrid(),
    OutfitBuilder(),
    WeatherPicker(),
    HistoryPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.locationWhenInUse].request();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Wardrobe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: Scaffold(
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: _widgetOptions,
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view),
              label: 'Гардероб',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.checkroom),
              label: 'Образ',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.wb_sunny),
              label: 'Погода',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'История',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Профиль',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.indigo,
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}

class GarmentsGrid extends StatefulWidget {
  const GarmentsGrid({super.key});

  @override
  State<GarmentsGrid> createState() => _GarmentsGridState();
}

class _GarmentsGridState extends State<GarmentsGrid> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _garments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGarments();
  }

  Future<void> _loadGarments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshot = await _db.collection('garments').orderBy('createdAt', descending: true).get();
      setState(() {
        _garments = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Без имени',
            'category': data['category'] ?? 'Общее',
            'color': data['color'] ?? 'Серый',
            'season': data['season'] ?? 'Лето',
            'imageUrl': data['imageUrl'] ?? '',
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _addGarment() async {
    final category = await _showDialog(
      'Добавить вещь', 
      {'name': 'Название', 'category': 'Категория', 'color': 'Цвет', 'season': 'Сезон'},
    );

    if (category != null) {
      final imageFile = await _picker.pickImage(source: ImageSource.gallery);
      String imageUrl = '';
      if (imageFile != null) {
        imageUrl = 'https://via.placeholder.com/300x400?text=${Uri.encodeComponent(category['name']!)}';
      }

      await _db.collection('garments').add({
        'name': category['name'],
        'category': category['category'],
        'color': category['color'],
        'season': category['season'],
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вещь добавлена!')),
      );
      _loadGarments();
    }
  }

  Future<Map<String, String>?> _showDialog(String title, Map<String, String> fields) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _BuildDialog(title: title, fields: fields),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGarments,
              child: const Text('Попробовать снова'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _garments.length,
            itemBuilder: (context, index) {
              final garment = _garments[index];
              return _GarmentCard(
                garment: garment,
                onDelete: () => _deleteGarment(garment['id']),
                onEdit: () => _editGarment(garment),
              );
            },
          ),
        ),
        if (_garments.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Нет вещей в гардеробе. Нажмите "+" чтобы добавить.',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _addGarment,
          icon: const Icon(Icons.add),
          label: const Text('Добавить вещь'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _deleteGarment(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить вещь?'),
        content: const Text('Вы уверены, что хотите удалить эту вещь?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.collection('garments').doc(id).delete();
      if (!mounted) return;
      _loadGarments();
    }
  }

  Future<void> _editGarment(Map<String, dynamic> garment) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditGarmentDialog(initial: garment),
    );

    if (result != null) {
      await _db.collection('garments').doc(garment['id']).update(result);
      if (!mounted) return;
      _loadGarments();
    }
  }
}

class _BuildDialog extends StatefulWidget {
  final String title;
  final Map<String, String> fields;

  const _BuildDialog({required this.title, required this.fields});

  @override
  State<_BuildDialog> createState() => _BuildDialogState();
}

class _BuildDialogState extends State<_BuildDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final key in widget.fields.keys) {
      _controllers[key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: widget.fields.keys.map((key) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: TextFormField(
                  controller: _controllers[key],
                  decoration: InputDecoration(labelText: key, border: const OutlineInputBorder()),
                  validator: (value) => (value == null || value.isEmpty) ? 'Введите $key' : null,
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final result = {};
              for (final key in widget.fields.keys) {
                result[key] = _controllers[key]!.text;
              }
              Navigator.of(context).pop(result);
            }
          },
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

class _EditGarmentDialog extends StatefulWidget {
  final Map<String, dynamic> initial;

  const _EditGarmentDialog({required this.initial});

  @override
  State<_EditGarmentDialog> createState() => _EditGarmentDialogState();
}

class _EditGarmentDialogState extends State<_EditGarmentDialog> {
  late TextEditingController _nameController;
  late TextEditingController _categoryController;
  late TextEditingController _colorController;
  late TextEditingController _seasonController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial['name'] ?? '');
    _categoryController = TextEditingController(text: widget.initial['category'] ?? '');
    _colorController = TextEditingController(text: widget.initial['color'] ?? '');
    _seasonController = TextEditingController(text: widget.initial['season'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _colorController.dispose();
    _seasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Название')),
            TextFormField(controller: _categoryController, decoration: const InputDecoration(labelText: 'Категория')),
            TextFormField(controller: _colorController, decoration: const InputDecoration(labelText: 'Цвет')),
            TextFormField(controller: _seasonController, decoration: const InputDecoration(labelText: 'Сезон')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'name': _nameController.text,
              'category': _categoryController.text,
              'color': _colorController.text,
              'season': _seasonController.text,
            });
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class OutfitBuilder extends StatefulWidget {
  const OutfitBuilder({super.key});

  @override
  State<OutfitBuilder> createState() => _OutfitBuilderState();
}

class _OutfitBuilderState extends State<OutfitBuilder> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Функция подбора образов\nдоступна после добавления вещей',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class WeatherPicker extends StatefulWidget {
  const WeatherPicker({super.key});

  @override
  State<WeatherPicker> createState() => _WeatherPickerState();
}

class _WeatherPickerState extends State<WeatherPicker> {
  String _selectedWeather = 'sunny';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Выберите погоду:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: ['sunny', 'rain', 'cloudy', 'snow'].map((w) {
              return ChoiceChip(
                label: Text(w.isEmpty ? w : w),
                selected: _selectedWeather == w,
                onSelected: (s) => setState(() => _selectedWeather = w),
              );
            }).toList(),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Подбор для $_selectedWeather')),
              );
            },
            child: const Text('Подобрать образ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('История образов\nбудет доступна скоро', textAlign: TextAlign.center),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userData = {
        'name': prefs.getString('name') ?? 'Пользователь',
        'email': prefs.getString('email') ?? '',
      };
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(radius: 50, backgroundColor: Colors.indigo, child: Icon(Icons.person, size: 50, color: Colors.white)),
          const SizedBox(height: 24),
          Text(_userData!['name'] ?? 'Имя', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_userData!['email'] ?? '', style: const TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _GarmentCard extends StatelessWidget {
  final Map<String, dynamic> garment;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _GarmentCard({required this.garment, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: garment['imageUrl'] != null && (garment['imageUrl'] as String).isNotEmpty
                  ? Image.network(
                      garment['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 80),
                    )
                  : const Container(color: Colors.grey, child: Icon(Icons.image, size: 80)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(garment['name'] ?? 'Без имени', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(garment['category'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(garment['color'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(TextButton(onPressed: onEdit, child: const Text('Ред.') const)),
                Expanded(TextButton(onPressed: onDelete, child: const Text('Удалить', style: TextStyle(color: Colors.red)))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}