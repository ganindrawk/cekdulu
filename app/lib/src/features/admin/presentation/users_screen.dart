import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';

/// Daftar pengguna ala mockup: header oranye, kolom cari + filter peran,
/// kartu pengguna, dan kartu total. Logika tidak berubah: daftar dari
/// profiles, ubah peran tetap lewat dialog (dulu dropdown di kartu).
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';
  String _roleFilter = 'Semua';

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

  Future<void> _changeRoleDialog(Map<String, dynamic> user) async {
    final role = (user['role'] ?? 'user').toString();
    final target = role == 'admin' ? 'user' : 'admin';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah peran'),
        content: Text(
          '${user['email']}\nPeran saat ini: $role. Ubah menjadi $target?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Jadikan $target'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _setRole((user['id'] ?? '').toString(), target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => context.go('/admin')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Cari email, nama, atau peran...',
                      hintStyle:
                          const TextStyle(color: Color(0xFF8A8A8A)),
                      prefixIcon: const Icon(Icons.search,
                          color: Color(0xFF8A8A8A)),
                      filled: true,
                      fillColor: const Color(0xFFF8F8F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFFE8E8E8)),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_list,
                          size: 20, color: Color(0xFF262626)),
                      const SizedBox(width: 2),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _roleFilter,
                          items: const [
                            DropdownMenuItem(
                                value: 'Semua',
                                child: Text('Semua Peran')),
                            DropdownMenuItem(
                                value: 'admin', child: Text('Admin')),
                            DropdownMenuItem(
                                value: 'user', child: Text('User')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _roleFilter = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return ErrorView(
                      message: snap.error.toString(), onRetry: _reload);
                }
                final all = snap.data ?? [];
                final q = _query.trim().toLowerCase();
                final users = all.where((u) {
                  if (_roleFilter != 'Semua' &&
                      (u['role'] ?? 'user').toString() != _roleFilter) {
                    return false;
                  }
                  if (q.isEmpty) return true;
                  final email =
                      (u['email'] ?? '').toString().toLowerCase();
                  final name =
                      (u['full_name'] ?? '').toString().toLowerCase();
                  final role =
                      (u['role'] ?? 'user').toString().toLowerCase();
                  return email.contains(q) ||
                      name.contains(q) ||
                      role.contains(q);
                }).toList();
                if (users.isEmpty) {
                  return const Center(
                      child: Text('Belum ada pengguna.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: users.length + 1,
                  itemBuilder: (context, i) {
                    if (i == users.length) {
                      return _TotalCard(count: all.length);
                    }
                    return _UserCard(
                      user: users[i],
                      onTap: () => _changeRoleDialog(users[i]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _UsersBottomNav(
        onTap: (route, usePush) {
          if (route == '/admin/users') return;
          usePush ? context.push(route) : context.go(route);
        },
      ),
    );
  }
}

/// Header oranye: tombol kembali, judul, subjudul, dan ilustrasi
/// avatar + roda gigi di kanan atas.
class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

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
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 28),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pengguna',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Kelola akun pengguna aplikasi CekDulu',
                        style: TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person,
                        size: 44, color: Colors.white),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.settings,
                          size: 17, color: Color(0xFFEE4D2D)),
                    ),
                  ),
                  const Positioned(
                    left: -14,
                    top: 2,
                    child: Icon(Icons.auto_awesome,
                        size: 20, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Satu kartu pengguna: avatar, email, pil peran, tanggal bergabung,
/// dan chevron. Ketuk kartu untuk ubah peran.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onTap});

  final Map<String, dynamic> user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = (user['role'] ?? 'user').toString();
    final isAdmin = role == 'admin';
    final fullName = (user['full_name'] ?? '').toString();
    final isActive = (user['is_active'] as bool?) ?? true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.08),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE7D9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person,
                      size: 32, color: Color(0xFFEE4D2D)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (user['email'] ?? '-').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF262626)),
                      ),
                      if (fullName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF8A8A8A)),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isAdmin
                              ? const Color(0xFFFFF0E8)
                              : const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person,
                                size: 14,
                                color: isAdmin
                                    ? const Color(0xFFEE4D2D)
                                    : const Color(0xFF2F7BFF)),
                            const SizedBox(width: 4),
                            Text(isAdmin ? 'Admin' : 'User',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isAdmin
                                        ? const Color(0xFFEE4D2D)
                                        : const Color(0xFF2F7BFF))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _StatusPill(active: isActive),
                    const SizedBox(height: 6),
                    Text(
                      'Bergabung: ${_formatDate(user['created_at'])}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A8A8A)),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Color(0xFF8A8A8A)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pil status kecil: Aktif (hijau) atau Nonaktif (abu-abu).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color =
        active ? const Color(0xFF2E9E57) : const Color(0xFF8A8A8A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEAF7EE) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(active ? 'Aktif' : 'Nonaktif',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

/// Kartu ringkasan di bawah daftar: jumlah pengguna terdaftar.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6F1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF7A29), Color(0xFFEE4D2D)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.manage_accounts,
                  size: 26, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Pengguna',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF262626))),
                  const SizedBox(height: 2),
                  Text('$count pengguna terdaftar',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF8A8A8A))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF8A8A8A)),
          ],
        ),
      ),
    );
  }
}

/// Bottom navigation ala mockup: Beranda / Katalog / Pengguna /
/// Pengaturan, dengan Pengguna aktif.
class _UsersBottomNav extends StatelessWidget {
  const _UsersBottomNav({required this.onTap});

  final void Function(String route, bool usePush) onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(Icons.home, 'Beranda', '/admin', false),
      _NavItem(Icons.storefront_outlined, 'Katalog', '/home', false),
      _NavItem(Icons.people, 'Pengguna', '/admin/users', false),
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
              final active = item.route == '/admin/users';
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

String _formatDate(dynamic value) {
  if (value == null) return '-';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return '-';
  final dt = parsed.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
