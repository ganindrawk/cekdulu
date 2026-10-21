import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';

/// Daftar pengguna + atur peran (admin saja).
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchUsers();
  }

  void _reload() {
    setState(() {
      _future = ref.read(adminRepositoryProvider).fetchUsers();
    });
  }

  Future<void> _setRole(String userId, String role) async {
    try {
      await ref.read(adminRepositoryProvider).setUserRole(userId, role);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Peran diubah menjadi $role')),
        );
      }
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengguna')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(
                message: snap.error.toString(), onRetry: _reload);
          }
          final users = snap.data ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('Belum ada pengguna.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, i) {
              final u = users[i];
              final role = (u['role'] ?? 'user').toString();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text((u['email'] ?? '-').toString()),
                  subtitle: Text('Peran: $role'),
                  trailing: DropdownButton<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(
                          value: 'user', child: Text('user')),
                      DropdownMenuItem(
                          value: 'admin', child: Text('admin')),
                    ],
                    onChanged: (v) {
                      if (v != null && v != role) {
                        _setRole((u['id'] ?? '').toString(), v);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
