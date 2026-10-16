import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Menyimpan status auth + peran untuk dipakai GoRouter redirect.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._repo) {
    _init();
  }

  final AuthRepository _repo;
  StreamSubscription<AuthState>? _sub;

  User? _user;
  String? _role;
  bool _ready = false;

  User? get user => _user;
  String? get role => _role;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _role == 'admin';
  bool get ready => _ready;

  Future<void> _init() async {
    if (!SupabaseConfig.isConfigured) {
      _ready = true;
      notifyListeners();
      return;
    }
    _user = _repo.currentUser;
    await _loadRole();
    _ready = true;
    notifyListeners();
    _sub = SupabaseConfig.client.auth.onAuthStateChange.listen((data) async {
      _user = data.session?.user;
      await _loadRole();
      notifyListeners();
    });
  }

  Future<void> _loadRole() async {
    _role = null;
    if (_user == null) return;
    try {
      _role = await _repo.fetchRole();
    } catch (_) {
      // Abaikan: mis. RLS / offline. Role dianggap non-admin.
    }
  }

  /// Dipanggil setelah login/register untuk memuat ulang peran.
  Future<void> refresh() async {
    _user = _repo.currentUser;
    await _loadRole();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final authNotifierProvider =
    ChangeNotifierProvider<AuthNotifier>((ref) => AuthNotifier(
          ref.watch(authRepositoryProvider),
        ));
