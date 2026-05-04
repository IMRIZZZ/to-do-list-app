import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TodoApp());
}

// ─────────────────────────────────────────────
// App root
// ─────────────────────────────────────────────
class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple To-Do',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const TodoHomePage(),
    );
  }

  ThemeData _buildTheme() {
    const seed = Color(0xFF5C6BC0); // indigo accent
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
      ),
      fontFamily: 'Roboto',
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.indigo.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: seed, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────
class Task {
  final String id;
  String title;
  bool isDone;
  final DateTime createdAt;

  Task({
    required this.id,
    required this.title,
    this.isDone = false,
    required this.createdAt,
  });

  // Serialisation helpers
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        isDone: json['isDone'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// Persistence helper
// ─────────────────────────────────────────────
class TaskStorage {
  static const _key = 'tasks_v1';

  static Future<List<Task>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }
}

// ─────────────────────────────────────────────
// Home page (stateful)
// ─────────────────────────────────────────────
class TodoHomePage extends StatefulWidget {
  const TodoHomePage({super.key});

  @override
  State<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  // ── lifecycle ──────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── storage helpers ────────────────────────
  Future<void> _loadTasks() async {
    final tasks = await TaskStorage.load();
    setState(() {
      _tasks = tasks;
      _isLoading = false;
    });
  }

  Future<void> _persist() => TaskStorage.save(_tasks);

  // ── task mutations ─────────────────────────
  void _addTask() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _tasks.insert(
        0,
        Task(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: text,
          createdAt: DateTime.now(),
        ),
      );
    });
    _inputController.clear();
    _inputFocus.unfocus();
    _persist();
  }

  void _toggleTask(String id) {
    setState(() {
      final idx = _tasks.indexWhere((t) => t.id == id);
      if (idx != -1) _tasks[idx].isDone = !_tasks[idx].isDone;
    });
    _persist();
  }

  void _deleteTask(String id) {
    setState(() => _tasks.removeWhere((t) => t.id == id));
    _persist();
  }

  void _clearCompleted() {
    setState(() => _tasks.removeWhere((t) => t.isDone));
    _persist();
  }

  // ── export ─────────────────────────────────
  Future<void> _exportJson() async {
    final jsonStr =
        const JsonEncoder.withIndent('  ').convert(_tasks.map((t) => t.toJson()).toList());
    await _shareText(jsonStr, 'tasks.json', 'application/json');
  }

  Future<void> _exportCsv() async {
    final rows = <List<dynamic>>[
      ['ID', 'Title', 'Done', 'Created At'],
      ..._tasks.map((t) => [
            t.id,
            t.title,
            t.isDone ? 'Yes' : 'No',
            t.createdAt.toIso8601String(),
          ]),
    ];
    final csvStr = const ListToCsvConverter().convert(rows);
    await _shareText(csvStr, 'tasks.csv', 'text/csv');
  }

  Future<void> _shareText(String content, String fileName, String mimeType) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(content);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType)],
        subject: 'My Task List',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _showExportDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export Tasks'),
        content: const Text('Choose a format to share or save your task list.'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.data_object_rounded),
            label: const Text('Export as JSON'),
            onPressed: () {
              Navigator.pop(ctx);
              _exportJson();
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.table_chart_rounded),
            label: const Text('Export as CSV'),
            onPressed: () {
              Navigator.pop(ctx);
              _exportCsv();
            },
          ),
        ],
      ),
    );
  }

  // ── computed ───────────────────────────────
  int get _completedCount => _tasks.where((t) => t.isDone).length;

  // ── build ──────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _buildAppBar(scheme),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildInputBar(scheme),
                if (_tasks.isNotEmpty) _buildProgressChip(scheme),
                Expanded(child: _buildTaskList(scheme)),
              ],
            ),
    );
  }

  AppBar _buildAppBar(ColorScheme scheme) {
    return AppBar(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      title: const Text(
        '📋  My To-Do List',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
      ),
      actions: [
        if (_completedCount > 0)
          IconButton(
            tooltip: 'Clear completed tasks',
            icon: const Icon(Icons.done_all_rounded),
            onPressed: _clearCompleted,
          ),
        IconButton(
          tooltip: 'Export tasks',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: _tasks.isEmpty ? null : _showExportDialog,
        ),
      ],
    );
  }

  Widget _buildInputBar(ColorScheme scheme) {
    return Container(
      color: scheme.primary.withOpacity(0.05),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocus,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _addTask(),
              decoration: const InputDecoration(
                hintText: 'Add a new task…',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _addTask,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Add', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressChip(ColorScheme scheme) {
    final total = _tasks.length;
    final done = _completedCount;
    final pct = (done / total * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$done / $total done  ($pct%)',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withOpacity(0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(ColorScheme scheme) {
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 72, color: scheme.primary.withOpacity(0.25)),
            const SizedBox(height: 16),
            Text(
              'All clear! Add a task above.',
              style: TextStyle(
                fontSize: 16,
                color: scheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _tasks.length,
      itemBuilder: (context, index) => _TaskCard(
        task: _tasks[index],
        onToggle: () => _toggleTask(_tasks[index].id),
        onDelete: () => _deleteTask(_tasks[index].id),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Task card widget
// ─────────────────────────────────────────────
class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDone = task.isDone;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: isDone
            ? scheme.surfaceContainerHighest.withOpacity(0.5)
            : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? scheme.outlineVariant.withOpacity(0.4)
              : scheme.outlineVariant,
          width: 1,
        ),
        boxShadow: isDone
            ? []
            : [
                BoxShadow(
                  color: scheme.shadow.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: Checkbox(
          value: isDone,
          onChanged: (_) => onToggle(),
          activeColor: scheme.primary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isDone ? FontWeight.normal : FontWeight.w500,
            color: isDone
                ? scheme.onSurface.withOpacity(0.4)
                : scheme.onSurface,
            decoration: isDone ? TextDecoration.lineThrough : null,
            decorationColor: scheme.onSurface.withOpacity(0.4),
          ),
        ),
        subtitle: Text(
          _formatDate(task.createdAt),
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurface.withOpacity(0.3),
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              color: scheme.error.withOpacity(isDone ? 0.4 : 0.7)),
          onPressed: onDelete,
          tooltip: 'Delete task',
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
