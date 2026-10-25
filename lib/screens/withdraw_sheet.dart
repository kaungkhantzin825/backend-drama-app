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
/// The payout destination is validated per method, because an approved request
/// with no destination is unpayable and would stall the admin queue.
class WithdrawSheet extends ConsumerStatefulWidget {
  const WithdrawSheet({super.key, required this.wallet});

  final Wallet wallet;

  @override
  ConsumerState<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<WithdrawSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _accountName = TextEditingController();
  final _accountNumber = TextEditingController();

  String _method = 'paypal';
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _accountName.dispose();
    _accountNumber.dispose();
    super.dispose();
  }

  Map<String, dynamic> _accountDetails() {
    return switch (_method) {
      'paypal' => {'email': _email.text.trim()},
      'bank' => {
          'account_name': _accountName.text.trim(),
          'account_number': _accountNumber.text.trim(),
        },
      // Gift cards are fulfilled manually, so no destination is needed up front.
      _ => <String, dynamic>{},
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    try {
      final withdrawal = await ref.read(walletApiProvider).requestWithdrawal(
            method: _method,
            accountDetails: _accountDetails(),
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
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'paypal', label: Text('PayPal'), icon: Icon(Icons.mail_outline, size: 15)),
                  ButtonSegment(value: 'bank', label: Text('Bank'), icon: Icon(Icons.account_balance_outlined, size: 15)),
                  ButtonSegment(value: 'giftcard', label: Text('Gift card'), icon: Icon(Icons.card_giftcard_outlined, size: 15)),
                ],
                selected: {_method},
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppTheme.accent.withValues(alpha: 0.18)
                        : AppTheme.surfaceHigh,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                  ),
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.selected)
                          ? AppTheme.accent.withValues(alpha: 0.5)
                          : AppTheme.divider,
                    ),
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                onSelectionChanged: (selection) => setState(() => _method = selection.first),
              ),
              const SizedBox(height: 16),
              ..._methodFields(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
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

  List<Widget> _methodFields() {
    switch (_method) {
      case 'paypal':
        return [
          _field(
            controller: _email,
            label: 'PayPal email',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'A PayPal email is required.';
              if (!text.contains('@') || !text.contains('.')) return 'Enter a valid email address.';
              return null;
            },
          ),
        ];
      case 'bank':
        return [
          _field(
            controller: _accountName,
            label: 'Account holder name',
            hint: 'As printed on the account',
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'An account name is required.' : null,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _accountNumber,
            label: 'Account number / IBAN',
            hint: 'Your account number',
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'An account number is required.' : null,
          ),
        ];
      default:
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.gold),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A digital gift card code is sent to your account email after approval.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ];
    }
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
