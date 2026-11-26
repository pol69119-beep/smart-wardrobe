import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

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
    _initStorage();
    _requestPermissions();
  }

  Future<void> _initStorage() async {
    final prefs = await SharedPreferences.getInstance();
    // Initialize any stored data here
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.location].request();
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
              icon: Icon(Icons.grid_on),
              label: 'Гардероб',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.fashion),
              label: 'Образ',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.weather),
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
        _garments = snapshot.docs.map((doc) => {
          'id': doc.id,
          'name': doc['name'] ?? 'Без имени',
          'category': doc['category'] ?? 'Категория',
          'color': doc['color'] ?? 'Серый',
          'season': doc['season'] ?? 'Сезон',
          'imageUrl': doc['imageUrl'] ?? '',
          'description': doc['description'] ?? '',
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _addGarment() async {
    final category = await _showDialog('Добавить вещь', {
      'name': 'Название',
      'category': 'Категория',
      'color': 'Цвет',
      'season': 'Сезон',
    });

    if (category != null) {
      final imageFile = await _picker.pickImage(source: ImageSource.gallery);
      String? imageUrl;
      if (imageFile != null) {
        // Загрузка изображения (заглушка - в реальном приложении загружаем на Firebase Storage)
        imageUrl = 'https://via.placeholder.com/300x400?text=${category['name']}';
      }

      await _db.collection('garments').add({
        'name': category['name'],
        'category': category['category'],
        'color': category['color'],
        'season': category['season'],
        'imageUrl': imageUrl,
        'description': '',
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxis(
              crossAxisCount: 2,
              mainAxisExtent: 250,
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
              'Нет вещей в гардеробе. Добавьте первую!',
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
        content: const Text('Вы уверены, что хотите удалить эту вещь из гардероба?'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вещь удалена')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вещь обновлена')),
      );
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
      _controllers[key] = TextEditingController(text: widget.fields[key]);
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
                  decoration: InputDecoration(
                    labelText: key,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Введите $key';
                    }
                    return null;
                  },
                );
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
                result[key] = _controllers[key].text;
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
      title: const Text('Редактировать вещь'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Название'),
              validator: (v) => v?.isEmpty ?? true ? 'Введите название' : null,
            ),
            TextFormField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Категория'),
            ),
            TextFormField(
              controller: _colorController,
              decoration: const InputDecoration(labelText: 'Цвет'),
            ),
            TextFormField(
              controller: _seasonController,
              decoration: const InputDecoration(labelText: 'Сезон'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подбор образа'),
      ),
      body: const Center(
        child: Text(
          'Функция подбора образов будет доступна скоро!\n\n'
          'В гардеробе сохраняйте вещи с категориями, цветом и сезоной,\n'
          'и система будет подбирать варианты для разных погод и событий.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Навигация к камере для добавления фото
        },
        child: const Icon(Icons.camera_alt),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Погода'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Выберите погоду для подображаемых образов:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _WeatherChip(
                  label: 'Солнечно',
                  value: 'sunny',
                  selected: _selectedWeather == 'sunny',
                  onSelected: (selected) {
                    setState(() => _selectedWeather = 'sunny');
                  },
                ),
                _WeatherChip(
                  label: 'Дождь',
                  value: 'rain',
                  selected: _selectedWeather == 'rain',
                  onSelected: (selected) {
                    setState(() => _selectedWeather = 'rain');
                  },
                ),
                _WeatherChip(
                  label: 'Облачно',
                  value: 'cloudy',
                  selected: _selectedWeather == 'cloudy',
                  onSelected: (selected) {
                    setState(() => _selectedWeather = 'cloudy');
                  },
                ),
                _WeatherChip(
                  label: 'Снег',
                  value: 'snow',
                  selected: _selectedWeather == 'snow',
                  onSelected: (selected) {
                    setState(() => _selectedWeather = 'snow');
                  },
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                // Поиск образов под выбранную погоду
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Подбор образов для $_selectedWeather погоды')),
                );
              },
              child: const Text('Подобрать образ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _WeatherChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: Colors.indigo,
      backgroundColor: Colors.grey[200],
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.indigo,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState;
}

class _HistoryPageState extends State<HistoryPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _outfits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _db.collection('outfits').orderBy('createdAt', descending: true).limit(20).get();
      setState(() {
        _outfits = snapshot.docs.map((doc) => {
          'id': doc.id,
          'title': doc['title'] ?? 'Образ',
          'garments': List<String>.from(doc['garments'] ?? []),
          'weather': doc['weather'] ?? 'sunny',
          'createdAt': doc['createdAt']?.toDate().toString() ?? '',
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        const Expanded(
          child: Center(
            child: Text(
              'История образов',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Expanded(
          child: _isLoading || _outfits.isEmpty
              ? const Center(child: Text('Нет сохраненных образов'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _outfits.length,
                  itemBuilder: (context, index) {
                    final outfit = _outfits[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.fashion),
                        title: Text(outfit['title']),
                        subtitle: Text('${outfit['garments'].length} вещей, ${outfit['weather']}'),
                        trailing: Text(
                          outfit['createdAt'].split(' ').first,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        onTap: () {
                          // Навигация к деталям образа
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final snapshot = await _db.collection('users').get();
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _userData = {
            'id': snapshot.docs.first.id,
            'name': snapshot.docs.first['name'] ?? 'Пользователь',
            'email': snapshot.docs.first['email'] ?? '',
            'createdAt': snapshot.docs.first['createdAt'],
          };
          _isLoading = false;
        });
      } else {
        // Создаем нового пользователя
        await _db.collection('users').add({
          'name': '',
          'email': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        setState(() {
          _userData = {
            'id': '',
            'name': '',
            'email': '',
            'createdAt': null,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
      ),
      body: Center(
        child: _userData == null
            ? const Text('Данные пользователя не найдены')
            : SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.person, size: 50, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _userData!['name'] ?? 'Имя',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _userData!['email'] ?? '',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit),
                      label: const Text('Редактировать профиль'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(200, 50),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class GarmentCard extends StatelessWidget {
  final Map<String, dynamic> garment;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const GarmentCard({
    required this.garment,
    required this.onDelete,
    required this.onEdit,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Изображение
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: garment['imageUrl'] != null && garment['imageUrl'].isNotEmpty
                  ? Image.network(
                      garment['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.image, size: 80, color: Colors.grey),
                    )
                  : const Container(
                      color: Colors.grey[300],
                      child: Icon(Icons.image, size: 80, color: Colors.grey),
                    ),
            ),
          ),
          // Информация
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  garment['name'] ?? 'Без имени',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.label, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      garment['category'] ?? '—',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Spacer(),
                    const Icon(Icons.color_lens, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      garment['color'] ?? '—',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      garment['season'] ?? '—',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Кнопки действий
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Редактировать'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.indigo,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                    label: const Text('Удалить'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}