import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/snackbar_helper.dart';
import '../../data/goals_repository.dart';

class GoalEditorSheet extends StatefulWidget {
  final Goal? existing;
  final String userId;
  final Future<void> Function(Goal) onSave;
  final VoidCallback? onDelete;

  const GoalEditorSheet({
    super.key,
    this.existing,
    required this.userId,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<GoalEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  String _emoji = '🎯';
  DateTime? _deadline;
  bool _saving = false;

  static const _emojis = [
    '🎯', '🏠', '✈️', '💻', '🚗', '💍', '🎓', '💊', '🛡️', '📱', '🎸', '⛺', '🏋️', '📚', '💎',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _targetCtrl.text = widget.existing!.targetAmount.toStringAsFixed(0);
      _emoji = widget.existing!.emoji;
      if (widget.existing!.deadline != null) {
        _deadline = DateTime.tryParse(widget.existing!.deadline!);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final target = double.tryParse(_targetCtrl.text);
    if (name.isEmpty) {
      showErrorSnackBar('Enter a goal name');
      return;
    }
    if (target == null || target <= 0) {
      showErrorSnackBar('Enter a valid target amount');
      return;
    }

    setState(() => _saving = true);
    try {
      final goal = Goal(
        id: widget.existing?.id,
        userId: widget.userId,
        name: name,
        emoji: _emoji,
        targetAmount: target,
        savedAmount: widget.existing?.savedAmount ?? 0,
        deadline: _deadline?.toIso8601String(),
        createdAt: widget.existing?.createdAt,
      );
      await widget.onSave(goal);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    isEdit ? 'Edit Goal' : 'New Goal',
                    style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (isEdit && widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFE53935)),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDelete!();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _emojis.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final e = _emojis[i];
                  final selected = e == _emoji;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF1A237E).withValues(alpha: 0.1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: selected ? Border.all(color: const Color(0xFF1A237E), width: 2) : null,
                      ),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Goal Name',
                      hintText: 'e.g. Emergency Fund',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _targetCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Target Amount (₹)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _deadline ?? DateTime.now().add(const Duration(days: 90)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                      );
                      if (picked != null) setState(() => _deadline = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 18, color: colors.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Text(
                            _deadline != null
                                ? 'Deadline: ${DateFormat('d MMM yyyy').format(_deadline!)}'
                                : 'Set deadline (optional)',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _deadline != null ? Colors.black87 : Colors.grey.shade500,
                            ),
                          ),
                          const Spacer(),
                          if (_deadline != null)
                            GestureDetector(
                              onTap: () => setState(() => _deadline = null),
                              child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
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
                              isEdit ? 'Save Changes' : 'Add Goal',
                              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
