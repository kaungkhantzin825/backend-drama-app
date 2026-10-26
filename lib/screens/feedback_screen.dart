import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../services/feedback_api.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// "Send feedback": a topic, a message and an optional way to reply. The
/// server stores it and emails it to the support team.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _contact = TextEditingController();

  String _category = 'bug';
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _sending = true);

    try {
      await ref.read(feedbackApiProvider).send(
            category: _category,
            message: _message.text.trim(),
            contact: _contact.text.trim(),
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, 'Thanks! Your feedback was sent.');
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(feedbackCategoriesProvider).valueOrNull ?? FeedbackApi.fallbackCategories;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Send feedback'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Tell us about a problem, a payment question or an idea. '
              'Our team reads every message.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 20),
            const _Label('Topic'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in categories)
                  ChoiceChip(
                    label: Text(category.label),
                    selected: category.key == _category,
                    showCheckmark: false,
                    selectedColor: AppTheme.accent.withValues(alpha: 0.18),
                    backgroundColor: AppTheme.surfaceHigh,
                    side: BorderSide(
                      color: category.key == _category
                          ? AppTheme.accent.withValues(alpha: 0.5)
                          : AppTheme.divider,
                    ),
                    labelStyle: TextStyle(
                      color: category.key == _category
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _category = category.key),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _Label('Message'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _message,
              minLines: 5,
              maxLines: 10,
              maxLength: 2000,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: _decoration('What happened? The more detail, the better.'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 5) return 'Please write a little more (at least 5 characters).';
                return null;
              },
            ),
            const SizedBox(height: 12),
            const _Label('Email or phone (optional)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contact,
              maxLength: 190,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: _decoration('So we can reply to you'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_sending ? 'Sending…' : 'Send feedback'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      filled: true,
      fillColor: AppTheme.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accent),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
