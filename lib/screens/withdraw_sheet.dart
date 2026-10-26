import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// The cash-out form.
///
/// The payment methods (KBZPay, WavePay, PayPal…) come from the admin's
/// settings. Every method asks for the account holder name plus one account
/// field, because an approved request with no destination is unpayable and
/// would stall the admin queue.
class WithdrawSheet extends ConsumerStatefulWidget {
  const WithdrawSheet({super.key, required this.wallet});

  final Wallet wallet;

  @override
  ConsumerState<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<WithdrawSheet> {
  final _formKey = GlobalKey<FormState>();
  final _accountName = TextEditingController();
  final _accountNumber = TextEditingController();

  late PayoutMethod? _method =
      widget.wallet.payoutMethods.isEmpty ? null : widget.wallet.payoutMethods.first;
  bool _submitting = false;

  @override
  void dispose() {
    _accountName.dispose();
    _accountNumber.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final method = _method;
    if (method == null || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    try {
      final withdrawal = await ref.read(walletApiProvider).requestWithdrawal(
            method: method.code,
            accountDetails: {
              'account_name': _accountName.text.trim(),
              'account_number': _accountNumber.text.trim(),
            },
          );

      if (!mounted) return;

      // The balance is now zero — reflect it immediately.
      await ref.read(walletProvider.notifier).refresh();
      ref.invalidate(ledgerProvider);
      ref.invalidate(withdrawalsProvider);

      if (!mounted) return;

      final navigator = Navigator.of(context);
      navigator.pop();
      showSnack(
        context,
        'Withdrawal requested for ${Fmt.cash(double.tryParse(withdrawal.amount) ?? 0, currency: withdrawal.currency)}.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showSnack(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = widget.wallet;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Request a withdrawal',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your whole balance is paid out in one request.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AMOUNT',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Fmt.cash(wallet.cashValue, currency: wallet.currency),
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '${Fmt.points(wallet.pointsBalance)} pts',
                      style: const TextStyle(color: AppTheme.gold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Payout method',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_method == null)
                const Text(
                  'Cash out is not available right now. Please try again later.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final method in wallet.payoutMethods)
                      ChoiceChip(
                        label: Text(method.name),
                        selected: method.code == _method?.code,
                        showCheckmark: false,
                        selectedColor: AppTheme.accent.withValues(alpha: 0.18),
                        backgroundColor: AppTheme.surfaceHigh,
                        side: BorderSide(
                          color: method.code == _method?.code
                              ? AppTheme.accent.withValues(alpha: 0.5)
                              : AppTheme.divider,
                        ),
                        labelStyle: TextStyle(
                          color: method.code == _method?.code
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setState(() => _method = method),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._methodFields(_method!),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting || _method == null ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit request'),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Payouts are reviewed manually and usually settle within 3–5 business days.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _methodFields(PayoutMethod method) {
    final isEmail = method.input == 'email';

    return [
      _field(
        controller: _accountName,
        label: 'Account holder name',
        hint: 'Name on your ${method.name} account',
        validator: (value) =>
            (value?.trim().isEmpty ?? true) ? 'Enter the account holder name.' : null,
      ),
      const SizedBox(height: 12),
      _field(
        controller: _accountNumber,
        label: method.accountLabel,
        hint: method.accountHint,
        keyboardType: switch (method.input) {
          'email' => TextInputType.emailAddress,
          'phone' => TextInputType.phone,
          _ => TextInputType.text,
        },
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Enter your ${method.accountLabel.toLowerCase()}.';
          if (isEmail && (!text.contains('@') || !text.contains('.'))) {
            return 'Enter a valid email address.';
          }
          return null;
        },
      ),
    ];
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
      ),
    );
  }
}
