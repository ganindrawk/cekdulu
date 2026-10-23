import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';

/// Dashboard admin: pintu masuk seluruh menu pengelolaan.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [
      _MenuItem(
        icon: Icons.inventory_2_outlined,
        title: 'Kelola Katalog',
        subtitle: 'Tambah / ubah / hapus produk',
        route: '/admin/products/new',
      ),
      _MenuItem(
        icon: Icons.key_outlined,
        title: 'Kredensial Affiliate',
        subtitle: 'Shopee API & ID affiliate',
        route: '/admin/credentials',
      ),
      _MenuItem(
        icon: Icons.auto_awesome_outlined,
        title: 'AI Pengenalan Gambar',
        subtitle: 'API key Gemini & model',
        route: '/admin/ai-settings',
      ),
      _MenuItem(
        icon: Icons.link_outlined,
        title: 'Link Affiliate',
        subtitle: 'Tempel link Shopee / Tokopedia per produk',
        route: '/admin/affiliate-links',
      ),
      _MenuItem(
        icon: Icons.people_outline,
        title: 'Pengguna',
        subtitle: 'Lihat & atur peran pengguna',
        route: '/admin/users',
      ),
      _MenuItem(
        icon: Icons.fingerprint,
        title: 'Akun & Sidik Jari',
        subtitle: 'Aktifkan login sidik jari',
        route: '/account',
        usePush: true,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin CekDulu'),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => item.usePush
                  ? context.push(item.route)
                  : context.go(item.route),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 40),
                    const SizedBox(height: 12),
                    Text(item.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(item.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuItem {
  _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.usePush = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  /// true = buka dengan push (bisa kembali), false = go.
  final bool usePush;
}
