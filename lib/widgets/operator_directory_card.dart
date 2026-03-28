import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/operator_contact.dart';
import '../providers/auth_provider.dart';
import '../providers/automation_hub_provider.dart';
import 'glass_card.dart';

class OperatorDirectoryCard extends StatefulWidget {
  const OperatorDirectoryCard({
    super.key,
    required this.auth,
  });

  final AuthProvider auth;

  @override
  State<OperatorDirectoryCard> createState() => _OperatorDirectoryCardState();
}

class _OperatorDirectoryCardState extends State<OperatorDirectoryCard> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsAppController = TextEditingController();
  final _telegramController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _whatsAppController.dispose();
    _telegramController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Enter the operator name first.');
      return;
    }

    if (_emailController.text.trim().isEmpty &&
        _phoneController.text.trim().isEmpty &&
        _telegramController.text.trim().isEmpty &&
        _whatsAppController.text.trim().isEmpty) {
      _showSnack('Add at least one communication channel.');
      return;
    }

    final contact = OperatorContact(
      id: 'contact-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      role: _roleController.text.trim().isEmpty
          ? 'Operations support'
          : _roleController.text.trim(),
      email: _emailController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      whatsAppNumber: _whatsAppController.text.trim(),
      telegramHandle: _telegramController.text.trim(),
      notes: _notesController.text.trim(),
    );

    await context.read<AutomationHubProvider>().addContact(contact);
    _nameController.clear();
    _roleController.clear();
    _emailController.clear();
    _phoneController.clear();
    _whatsAppController.clear();
    _telegramController.clear();
    _notesController.clear();
    _showSnack('Operator contact saved for handoff and repair coordination.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openUri(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showSnack('This device could not open ${uri.toString()}.');
    }
  }

  String _digitsOnly(String value) {
    final buffer = StringBuffer();
    for (final char in value.runes) {
      final text = String.fromCharCode(char);
      if (RegExp(r'[0-9]').hasMatch(text)) {
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<AutomationHubProvider>();
    final isAdmin = widget.auth.isAdmin;

    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC0A1626),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OPERATOR DIRECTORY',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Save shift, repair, and escalation contacts so humans can take over when automation misleads or goes down.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _RoleChip(
                label: isAdmin ? 'Admin edit access' : 'Read-only roster',
                accent:
                    isAdmin ? const Color(0xFF2DD4BF) : const Color(0xFFF59E0B),
              ),
            ],
          ),
          if (isAdmin) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _InputField(
                  controller: _nameController,
                  label: 'Operator name',
                ),
                _InputField(
                  controller: _roleController,
                  label: 'Role',
                ),
                _InputField(
                  controller: _emailController,
                  label: 'Email',
                ),
                _InputField(
                  controller: _phoneController,
                  label: 'Phone',
                ),
                _InputField(
                  controller: _whatsAppController,
                  label: 'WhatsApp',
                ),
                _InputField(
                  controller: _telegramController,
                  label: 'Telegram',
                ),
                _InputField(
                  controller: _notesController,
                  label: 'Notes',
                  width: 520,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saveContact,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Save operator contact'),
            ),
          ] else ...[
            const SizedBox(height: 18),
            const Text(
              'Only admin accounts can add or remove contacts. Every operator can still open the communication links below during a repair handoff.',
              style: TextStyle(color: Colors.white60, height: 1.45),
            ),
          ],
          const SizedBox(height: 22),
          for (final contact in hub.contacts) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contact.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              contact.role,
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      if (isAdmin)
                        IconButton(
                          tooltip: 'Delete contact',
                          onPressed: () {
                            context
                                .read<AutomationHubProvider>()
                                .removeContact(contact.id);
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: const Color(0xFFFB7185),
                        ),
                    ],
                  ),
                  if (contact.notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      contact.notes,
                      style:
                          const TextStyle(color: Colors.white70, height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (contact.email.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openUri(
                            Uri(
                              scheme: 'mailto',
                              path: contact.email,
                            ),
                          ),
                          icon: const Icon(Icons.email_outlined),
                          label: Text(contact.email),
                          style: _contactButtonStyle(),
                        ),
                      if (contact.phoneNumber.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openUri(
                            Uri(
                              scheme: 'tel',
                              path: contact.phoneNumber,
                            ),
                          ),
                          icon: const Icon(Icons.phone_outlined),
                          label: Text(contact.phoneNumber),
                          style: _contactButtonStyle(),
                        ),
                      if (contact.whatsAppNumber.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openUri(
                            Uri.parse(
                              'https://wa.me/${_digitsOnly(contact.whatsAppNumber)}',
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          label: const Text('WhatsApp'),
                          style: _contactButtonStyle(),
                        ),
                      if (contact.telegramHandle.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openUri(
                            Uri.parse(
                              'https://t.me/${contact.telegramHandle.replaceFirst('@', '')}',
                            ),
                          ),
                          icon: const Icon(Icons.send_outlined),
                          label: Text(
                              '@${contact.telegramHandle.replaceFirst('@', '')}'),
                          style: _contactButtonStyle(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (contact != hub.contacts.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  ButtonStyle _contactButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    this.width = 240,
  });

  final TextEditingController controller;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF38BDF8)),
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: accent.withValues(alpha: 0.16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
