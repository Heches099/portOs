import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/glass_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _operatorController = TextEditingController();
  final _accessKeyController = TextEditingController();
  String? _operatorError;
  String? _accessKeyError;
  bool _isHovering = false;

  @override
  void dispose() {
    _operatorController.dispose();
    _accessKeyController.dispose();
    super.dispose();
  }

  bool _validateInputs() {
    setState(() {
      _operatorError = _validateOperator(_operatorController.text.trim());
      _accessKeyError = _validateAccessKey(_accessKeyController.text);
    });

    return _operatorError == null && _accessKeyError == null;
  }

  String? _validateOperator(String value) {
    if (value.isEmpty) {
      return 'Operator ID is required';
    }

    final emailRegex = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Enter a valid operator email';
    }

    return null;
  }

  String? _validateAccessKey(String value) {
    if (value.isEmpty) {
      return 'Access key is required';
    }
    if (value.length < 6) {
      return 'Access key must be at least 6 characters';
    }
    return null;
  }

  Future<void> _handleInitialize() async {
    final authProvider = context.read<AuthProvider>();
    if (!_validateInputs()) {
      return;
    }

    final notificationProvider = context.read<NotificationProvider>();

    try {
      final success = await authProvider.signIn(
        email: _operatorController.text.trim(),
        password: _accessKeyController.text,
      );

      if (!mounted || !success) {
        return;
      }

      notificationProvider.push(
        title: 'Command center initialized',
        message: 'Operator ${authProvider.displayName} authenticated.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('System initialization failed: $error')),
      );
    }
  }

  Future<void> _handleForgotPassword() async {
    final authProvider = context.read<AuthProvider>();
    final email = _operatorController.text.trim();
    final emailError = _validateOperator(email);
    if (emailError != null) {
      setState(() {
        _operatorError = emailError;
      });
      return;
    }

    try {
      await authProvider.sendPasswordResetEmail(email: email);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset email sent to the registered operator address.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isWideLayout = MediaQuery.of(context).size.width >= 980;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E293B),
                  Color(0xFF334155),
                ],
              ),
            ),
          ),
          const Positioned(
            top: -140,
            right: -80,
            child: _AmbientGlow(
              size: 320,
              color: Color(0x3348A7FF),
            ),
          ),
          const Positioned(
            bottom: -120,
            left: -40,
            child: _AmbientGlow(
              size: 260,
              color: Color(0x2210B981),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWideLayout ? 1080 : 440,
                  ),
                  child: isWideLayout
                      ? Row(
                          children: [
                            const Expanded(child: _LoginNarrative()),
                            const SizedBox(width: 28),
                            Expanded(
                              child: _LoginPanel(
                                authProvider: authProvider,
                                operatorController: _operatorController,
                                accessKeyController: _accessKeyController,
                                operatorError: _operatorError,
                                accessKeyError: _accessKeyError,
                                isHovering: _isHovering,
                                onHoverChanged: (value) {
                                  setState(() => _isHovering = value);
                                },
                                onChanged: () {
                                  setState(() {
                                    _operatorError = null;
                                    _accessKeyError = null;
                                  });
                                },
                                onInitialize: _handleInitialize,
                                onForgotPassword: _handleForgotPassword,
                              ),
                            ),
                          ],
                        )
                      : _LoginPanel(
                          authProvider: authProvider,
                          operatorController: _operatorController,
                          accessKeyController: _accessKeyController,
                          operatorError: _operatorError,
                          accessKeyError: _accessKeyError,
                          isHovering: _isHovering,
                          onHoverChanged: (value) {
                            setState(() => _isHovering = value);
                          },
                          onChanged: () {
                            setState(() {
                              _operatorError = null;
                              _accessKeyError = null;
                            });
                          },
                          onInitialize: _handleInitialize,
                          onForgotPassword: _handleForgotPassword,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.authProvider,
    required this.operatorController,
    required this.accessKeyController,
    required this.operatorError,
    required this.accessKeyError,
    required this.isHovering,
    required this.onHoverChanged,
    required this.onChanged,
    required this.onInitialize,
    required this.onForgotPassword,
  });

  final AuthProvider authProvider;
  final TextEditingController operatorController;
  final TextEditingController accessKeyController;
  final String? operatorError;
  final String? accessKeyError;
  final bool isHovering;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onChanged;
  final VoidCallback onInitialize;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 260),
        scale: isHovering ? 1.01 : 1,
        child: GlassCard(
          padding: const EdgeInsets.all(40),
          borderRadius: 40,
          color: Colors.white.withValues(alpha: 0.08),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Icon(
                  Icons.blur_on_rounded,
                  color: Color(0xFF60A5FA),
                  size: 80,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'PORT OS',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                ),
              ),
              Center(
                child: Text(
                  'AUTONOMOUS TERMINAL INTERFACE',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white54,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
              if (authProvider.statusMessage != null) ...[
                const SizedBox(height: 28),
                _InfoStrip(message: authProvider.statusMessage!),
              ],
              const SizedBox(height: 36),
              _CommandField(
                controller: operatorController,
                hint: 'OPERATOR ID',
                icon: Icons.person_outline,
                errorText: operatorError,
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: 16),
              _CommandField(
                controller: accessKeyController,
                hint: 'ACCESS KEY',
                icon: Icons.lock_outline,
                obscureText: true,
                errorText: accessKeyError,
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: authProvider.isLoading ? null : onForgotPassword,
                  child: const Text('Forgot access key?'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Operator accounts are created manually in Firebase Console.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: authProvider.isLoading ? null : onInitialize,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: isHovering ? 20 : 0,
                  ),
                  child: authProvider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'INITIALIZE SYSTEM',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Only Firebase-authenticated operators can reach the live command-center data path.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      height: 1.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginNarrative extends StatelessWidget {
  const _LoginNarrative();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'MAJESTIC PORT OS',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF60A5FA),
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 20),
          Text(
            'Realtime terminal control, architected for FastAPI, Firestore, and edge AI.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
          ),
          const SizedBox(height: 18),
          Text(
            'This layout is now organized around service, provider, model, and screen layers so the UI can grow into a real command center instead of staying a monolithic prototype.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 28),
          const _NarrativePoint(
            title: 'FastAPI orchestration',
            detail:
                'Accept crane, RFID, and gate events, normalize them, then publish realtime state for operators.',
          ),
          const SizedBox(height: 16),
          const _NarrativePoint(
            title: 'Firestore-ready sync',
            detail:
                'Live Firestore snapshots are available after Firebase is configured and an operator signs in.',
          ),
          const SizedBox(height: 16),
          const _NarrativePoint(
            title: 'Edge vision expansion',
            detail:
                'CCTV modules can evolve into RTSP-to-WebRTC streams and AI overlays without reshaping the shell.',
          ),
        ],
      ),
    );
  }
}

class _CommandField extends StatelessWidget {
  const _CommandField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.errorText,
    this.obscureText = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final bool obscureText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white38),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        errorText: errorText,
        errorStyle: const TextStyle(color: Color(0xFFFCA5A5)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF60A5FA)),
        ),
      ),
    );
  }
}

class _NarrativePoint extends StatelessWidget {
  const _NarrativePoint({
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF60A5FA),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF60A5FA)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
