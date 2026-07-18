import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/recording.dart';
import '../../../data/repositories/recording_repository.dart';
import '../../../shared/widgets/glass.dart';
import '../../auth/providers/auth_provider.dart';
import '../../goals/goals_screen.dart';
import '../../questions/screens/question_bank_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _displayName(User? user) {
    final name = user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final local = (user?.email ?? '').split('@').first;
    if (local.isEmpty) return 'Your Profile';
    return local[0].toUpperCase() + local.substring(1);
  }

  String _initial(User? user) {
    final source = _displayName(user);
    return source.isNotEmpty ? source[0].toUpperCase() : '?';
  }

  // Bottom sheet that lets the user change their display name.
  Future<void> _editProfile(User user) async {
    final controller = TextEditingController(text: user.displayName ?? '');

    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: (size.width * 0.06).clamp(16.0, 32.0),
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: AppColors.separator,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      'Edit Profile',
                      style: TextStyle(
                        color: AppColors.wine,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      user.email ?? '',
                      style: const TextStyle(
                        color: AppColors.midMauve,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        hintText: 'e.g. Jane Doe',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      onSubmitted: (v) =>
                          Navigator.of(sheetContext).pop(v.trim()),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () => Navigator.of(sheetContext)
                                .pop(controller.text.trim()),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (newName == null || newName.isEmpty || !mounted) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.updateDisplayName(newName);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Profile updated'
              : 'Could not update profile: ${auth.errorMessage ?? 'Unknown error'}',
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().signOut();
    }
  }

  // Asks the user to confirm their password, then permanently deletes their
  // account and all their recordings. On success AuthWrapper routes back to
  // the login screen automatically.
  Future<void> _confirmDeleteAccount(User user) async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes your account and all your '
                  'recordings. This cannot be undone.\n\n'
                  'Enter your password to confirm.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Password is required' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    final userId = user.uid;
    final ok = await auth.deleteAccount(
      passwordController.text,
      beforeDelete: () =>
          RecordingRepository().deleteAllRecordings(userId),
    );

    if (!mounted) return;
    if (!ok && auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
          children: [
            // ===== Halo avatar header =====
            Center(
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0A84FF), Color(0xFF5BC0FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0A5ADC)
                              .withValues(alpha: 0.55),
                          blurRadius: 36,
                          offset: const Offset(0, 18),
                          spreadRadius: -14,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.55),
                          spreadRadius: 6,
                        ),
                        BoxShadow(
                          color: const Color(0xFF7896C8)
                              .withValues(alpha: 0.18),
                          spreadRadius: 7,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initial(user),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _displayName(user),
                    style: const TextStyle(
                      color: AppColors.wine,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email ?? '',
                    style: const TextStyle(
                      color: AppColors.midMauve,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MemberPill(userId: user.uid),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // ===== Account section =====
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Text(
                'Account',
                style: TextStyle(
                  color: AppColors.wine,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _setRow(
                    colors: const [Color(0xFF0A84FF), Color(0xFF3FA9FF)],
                    icon: Icons.person_rounded,
                    title: 'Edit Profile',
                    onTap: () => _editProfile(user),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 60,
                    color: AppColors.separator,
                  ),
                  _setRow(
                    colors: const [Color(0xFFFF9F0A), Color(0xFFFF6B00)],
                    icon: Icons.local_fire_department_rounded,
                    title: 'Practice goals',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GoalsScreen()),
                    ),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 60,
                    color: AppColors.separator,
                  ),
                  _setRow(
                    colors: const [Color(0xFF5E6AD2), Color(0xFF8C99F0)],
                    icon: Icons.quiz_rounded,
                    title: 'Interview questions',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const QuestionBankScreen()),
                    ),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 60,
                    color: AppColors.separator,
                  ),
                  _setRow(
                    colors: const [Color(0xFF64708B), Color(0xFF8C99B3)],
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ===== Sign out =====
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 16),
              onTap: _confirmLogout,
              child: const Center(
                child: Text(
                  'Sign out',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ===== Delete account =====
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 16),
              onTap: () => _confirmDeleteAccount(user),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_forever_rounded,
                        color: AppColors.danger, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Delete account',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // iOS Settings-style row: gradient icon square, label, chevron.
  Widget _setRow({
    required List<Color> colors,
    required IconData icon,
    required String title,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.wine,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.softMauve, size: 20),
          ],
        ),
      ),
    );
  }
}

// "N practice sessions" pill, fed live from Firestore.
class _MemberPill extends StatefulWidget {
  final String userId;

  const _MemberPill({required this.userId});

  @override
  State<_MemberPill> createState() => _MemberPillState();
}

class _MemberPillState extends State<_MemberPill> {
  late final Stream<List<Recording>> _stream =
      RecordingRepository().watchRecordings(widget.userId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Recording>>(
      stream: _stream,
      builder: (context, snapshot) {
        final n = snapshot.data?.length ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            '$n practice session${n == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.tintDeep,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
