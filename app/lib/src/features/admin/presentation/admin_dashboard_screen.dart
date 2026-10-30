import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';

/// Dashboard admin ala mockup: header oranye, kartu menu 2 kolom,
/// dan bottom navigation (Dashboard / Produk / Affiliate / Pengguna /
/// Pengaturan). Semua tujuan menu sama seperti sebelumnya, hanya
/// tampilannya yang berubah.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [
      _MenuItem(
        icon: Icons.inventory_2,
        title: 'Kelola Katalog',
        subtitle: 'Tambah / ubah / hapus produk',
        route: '/admin/products/new',
        gradient: const [Color(0xFFFF7A29), Color(0xFFFF8A3D)],
      ),
      _MenuItem(
        icon: Icons.key,
        title: 'Kredensial Affiliate',
        subtitle: 'Shopee API & ID affiliate',
        route: '/admin/credentials',
        gradient: const [Color(0xFFFFB020), Color(0xFFFFA726)],
      ),
      _MenuItem(
        icon: Icons.auto_awesome,
        title: 'AI Pengenalan Gambar',
        subtitle: 'API key Gemini & model',
        route: '/admin/ai-settings',
        gradient: const [Color(0xFFFF6B6B), Color(0xFFFF7A6B)],
      ),
      _MenuItem(
        icon: Icons.link,
        title: 'Link Affiliate',
        subtitle: 'Tempel link Shopee / Tokopedia per produk',
        route: '/admin/affiliate-links',
        gradient: const [Color(0xFFFF5A3C), Color(0xFFFF6B4A)],
      ),
      _MenuItem(
        icon: Icons.people,
        title: 'Pengguna',
        subtitle: 'Lihat & atur peran pengguna',
        route: '/admin/users',
        gradient: const [Color(0xFFFF7A29), Color(0xFFFF8A3D)],
      ),
      _MenuItem(
        icon: Icons.fingerprint,
        title: 'Akun & Sidik Jari',
        subtitle: 'Aktifkan login sidik jari',
        route: '/account',
        usePush: true,
        gradient: const [Color(0xFFFF4D2D), Color(0xFFFF6B4A)],
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF6F1),
      body: Column(
        children: [
          _Header(
            onLogout: () async {
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
          Expanded(
            child: Stack(
              children: [
                GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _MenuCard(
                      item: item,
                      onTap: () => item.usePush
                          ? context.push(item.route)
                          : context.go(item.route),
                    );
                  },
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(child: _HillsDecoration(height: 110)),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _AdminBottomNav(
        onTap: (route, usePush) {
          if (route == '/admin') return;
          usePush ? context.push(route) : context.go(route);
        },
      ),
    );
  }
}

/// Header oranye dengan avatar, sapaan, dan tombol keluar.
class _Header extends StatelessWidget {
  const _Header({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B35), Color(0xFFEE4D2D)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Stack(
        children: [
          // Dekorasi samar: keranjang & tas belanja di kanan atas.
          const Positioned(
            right: 56,
            top: 58,
            child: Icon(Icons.shopping_cart_outlined,
                size: 54, color: Colors.white24),
          ),
          const Positioned(
            right: 6,
            top: 34,
            child: Icon(Icons.shopping_bag_outlined,
                size: 88, color: Colors.white24),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 28),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person,
                        size: 34, color: Color(0xFFEE4D2D)),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin CekDulu',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text('Selamat datang kembali!',
                            style: TextStyle(
                                color: Colors.white, fontSize: 15)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Keluar',
                    icon: const Icon(Icons.logout, color: Colors.white),
                    onPressed: onLogout,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu kartu menu: ikon gradasi, chevron, judul, dan subjudul.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.item, required this.onTap});

  final _MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: item.gradient,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(item.icon, size: 30, color: Colors.white),
                  ),
                  const Spacer(),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF0E8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_right,
                        size: 20, color: Color(0xFFEE4D2D)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(item.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700,
                      color: Color(0xFF262626))),
              const SizedBox(height: 4),
              Text(item.subtitle,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF8A8A8A), height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bukit oranye dekoratif di bawah grid, dengan ikon samar.
class _HillsDecoration extends StatelessWidget {
  const _HillsDecoration({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _HillsPainter(),
          ),
          const Positioned(
            left: 24,
            bottom: 34,
            child: Icon(Icons.shopping_cart_outlined,
                size: 44, color: Colors.white38),
          ),
          const Positioned(
            left: 84,
            bottom: 14,
            child: Icon(Icons.local_offer_outlined,
                size: 30, color: Colors.white38),
          ),
          const Positioned(
            right: 74,
            bottom: 40,
            child: Icon(Icons.shopping_bag_outlined,
                size: 46, color: Colors.white38),
          ),
          const Positioned(
            right: 22,
            bottom: 18,
            child: Icon(Icons.percent_outlined,
                size: 30, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

class _HillsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final back = Paint()..color = const Color(0xFFFFCDB8);
    final front = Paint()..color = const Color(0xFFFF8A50);
    final w = size.width;
    final h = size.height;
    // Bukit belakang (lebih muda).
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.55)
        ..quadraticBezierTo(w * 0.25, h * 0.05, w * 0.55, h * 0.5)
        ..quadraticBezierTo(w * 0.8, h * 0.85, w, h * 0.4)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      back,
    );
    // Bukit depan (lebih pekat).
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.75)
        ..quadraticBezierTo(w * 0.3, h * 0.3, w * 0.6, h * 0.7)
        ..quadraticBezierTo(w * 0.85, h * 0.95, w, h * 0.6)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      front,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bottom navigation admin: Dashboard aktif, sisanya abu-abu.
class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({required this.onTap});

  final void Function(String route, bool usePush) onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(Icons.home, 'Dashboard', '/admin', false),
      _NavItem(Icons.inventory_2_outlined, 'Produk', '/admin/products/new',
          false),
      _NavItem(Icons.link_outlined, 'Affiliate', '/admin/affiliate-links',
          false),
      _NavItem(Icons.people_outline, 'Pengguna', '/admin/users', false),
      _NavItem(Icons.settings_outlined, 'Pengaturan', '/account', true),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: items.map((item) {
              final active = item.route == '/admin';
              final color = active
                  ? const Color(0xFFEE4D2D)
                  : const Color(0xFF8A8A8A);
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(item.route, item.usePush),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 26, color: color),
                      const SizedBox(height: 2),
                      Text(item.label,
                          style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label, this.route, this.usePush);

  final IconData icon;
  final String label;
  final String route;
  final bool usePush;
}

class _MenuItem {
  _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.gradient,
    this.usePush = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final List<Color> gradient;

  /// true = buka dengan push (bisa kembali), false = go.
  final bool usePush;
}
