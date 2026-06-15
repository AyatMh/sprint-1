import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream that emits the current user (or null) whenever auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signUp({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user;
  }

  Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user;
  }

  Future<void> signOut() => _auth.signOut();

  // Updates the signed-in user's display name and reloads so the local
  // user object reflects the change.
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(name);
    await user.reload();
  }

  // Permanently deletes the current user's account. Firebase requires a
  // recent login for this, so we re-authenticate with the password first.
  // [beforeDelete] runs after re-auth but before the account is removed —
  // use it to clean up the user's data (e.g. their recordings) while they
  // are still authenticated.
  Future<void> deleteAccount({
    required String password,
    Future<void> Function()? beforeDelete,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final email = user.email;
    if (email != null) {
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(credential);
    }

    if (beforeDelete != null) {
      await beforeDelete();
    }

    await user.delete();
  }

  // Converts cryptic Firebase error codes into user-friendly messages
  String mapErrorToMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'An account already exists for this email.';
        case 'invalid-email':
          return 'That email address looks invalid.';
        case 'weak-password':
          return 'Password is too weak (min 6 characters).';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Wrong email or password.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'network-request-failed':
          return 'Network error. Check your connection.';
        case 'too-many-requests':
          return 'Too many attempts. Try again later.';
        case 'requires-recent-login':
          return 'Please sign in again before deleting your account.';
        default:
          return e.message ?? 'Authentication failed.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}