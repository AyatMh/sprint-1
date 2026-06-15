import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../../data/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  bool _loading = false;
  String? _errorMessage;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  AuthService get authService => _authService;

  AuthProvider() {
    // Listen to Firebase auth changes and update our state
    _authService.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<bool> signUp(String email, String password) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _authService.signUp(email: email, password: password);
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = _authService.mapErrorToMessage(e);
      _setLoading(false);
      return false;
    }
  }

  Future<bool> signIn(String email, String password) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _authService.signIn(email: email, password: password);
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = _authService.mapErrorToMessage(e);
      _setLoading(false);
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }

  // Updates the display name, then refreshes the cached user and notifies
  // listeners so the new name shows everywhere (home greeting, avatar, etc.).
  Future<bool> updateDisplayName(String name) async {
    _errorMessage = null;
    try {
      await _authService.updateDisplayName(name);
      _user = _authService.currentUser;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = _authService.mapErrorToMessage(e);
      notifyListeners();
      return false;
    }
  }

  // Re-authenticates with [password], runs [beforeDelete] to clean up the
  // user's data, then permanently deletes the account. Returns true on
  // success; on failure sets [errorMessage] and returns false.
  Future<bool> deleteAccount(
    String password, {
    Future<void> Function()? beforeDelete,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _authService.deleteAccount(
        password: password,
        beforeDelete: beforeDelete,
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = _authService.mapErrorToMessage(e);
      _setLoading(false);
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}