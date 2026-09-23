import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/utils/inr_amount_input_formatter.dart';
import '../../data/goals_repository.dart';

class GoalTopUpSheet extends StatefulWidget {
  final Goal goal;
  final Future<void> Function(double amount) onTopUp;

  const GoalTopUpSheet({super.key, required this.goal, required this.onTopUp});

  @override
  State<GoalTopUpSheet> createState() => _GoalTopUpSheetState();
}

class _GoalTopUpSheetState extends State<GoalTopUpSheet> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  final _fmt = NumberFormat('#,##,##0', 'en_IN');

  double get _remaining => widget.goal.targetAmount - widget.goal.savedAmount;

  void _onAmountChanged() => setState(() {});

  double? _parseRupee(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onAmountChanged);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = _parseRupee(_ctrl.text);
    if (amount == null || amount <= 0) {
      showErrorSnackBar('Enter a valid amount');
      return;
    }
    if (amount > _remaining + 0.01) {
      showErrorSnackBar('Cannot exceed remaining ₹${_fmt.format(_remaining.round())}');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onTopUp(amount);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final typed = _parseRupee(_ctrl.text);
    final previewAdd = typed != null && typed > 0 ? typed.clamp(0.0, _remaining) : 0.0;
    final previewSaved = goal.savedAmount + previewAdd;
    final previewRemaining = goal.targetAmount - previewSaved;
    final previewPct = goal.targetAmount > 0 ? (previewSaved / goal.targetAmount).clamp(0.0, 1.0) : 0.0;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Text('${goal.emoji} Add money', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(goal.name, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹${_fmt.format(previewSaved.round())} saved',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  Text(
                    '₹${_fmt.format(previewRemaining < 0 ? 0 : previewRemaining.round())} left',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A237E)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: previewPct.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade100,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1A237E)),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [500, 1000, 2000, 5000].map((amt) {
                  final capped = amt > _remaining ? _remaining : amt.toDouble();
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        onPressed: () {
                          final text = _fmt.format(capped.round());
                          _ctrl.value = TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(offset: text.length),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(
                          '₹${_fmt.format(capped.round())}',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  InrAmountInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  prefixText: '₹ ',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: _saving ? null : _submit,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _saving ? Colors.grey.shade300 : const Color(0xFF1A237E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Add money',
                          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
    );
  }
}
