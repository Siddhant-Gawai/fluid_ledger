import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/constants/categories.dart'
    show defaultCategories, matchMerchant;
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/transaction_repository.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, this.initialCategoryName});

  /// Category name from [defaultCategories] (e.g. from dashboard quick actions).
  final String? initialCategoryName;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  int _selectedCategory = -1;
  bool _isSaving = false;
  bool _showAllCategories = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialCategoryName?.trim();
    if (raw == null || raw.isEmpty) return;
    final key = raw.toLowerCase() == 'transport' ? 'travel' : raw;
    final idx = defaultCategories.indexWhere(
      (c) => c.name.toLowerCase() == key.toLowerCase(),
    );
    if (idx < 0) return;
    _selectedCategory = idx;
    if (idx >= 8) _showAllCategories = true;
  }

  Future<void> _saveTransaction() async {
    final amountText = _amountController.text.replaceAll(',', '');
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) return;
    if (_selectedCategory < 0) return;

    final category = defaultCategories[_selectedCategory];

    setState(() => _isSaving = true);

    try {
      final notesText = _notesController.text.isEmpty
          ? null
          : _notesController.text;
      final matched = matchMerchant(notesText);
      final newTransaction = TransactionData(
        amount: amount,
        category: category.name,
        date: DateTime.now().toIso8601String(),
        notes: notesText,
        brand: matched?.name,
      );

      await ref
          .read(transactionRepositoryProvider)
          .insertTransaction(newTransaction);
      if (mounted) {
        context.pop();
        showSuccessSnackBar(
          '₹${amount.toStringAsFixed(0)} added to ${category.name} ${category.emoji}',
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar('Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedCategory = _selectedCategory >= 0
        ? defaultCategories[_selectedCategory]
        : null;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Add Expense',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.primary,
                          colors.primaryContainer,
                          const Color(0xFF4F66C5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.22),
                          blurRadius: 26,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEW EXPENSE',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.7),
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Log an amount first. Categorize it after.',
                          style: GoogleFonts.manrope(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: IntrinsicWidth(
                            child: TextField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.,]'),
                                ),
                              ],
                              textAlign: TextAlign.center,
                              autofocus: true,
                              onChanged: (_) => setState(() {}),
                              style: GoogleFonts.manrope(
                                fontSize: 52,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                              decoration: InputDecoration(
                                prefixText: '₹ ',
                                prefixStyle: GoogleFonts.manrope(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                border: InputBorder.none,
                                hintText: '0',
                                hintStyle: GoogleFonts.manrope(
                                  fontSize: 52,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withValues(alpha: 0.28),
                                ),
                                filled: false,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _notesController,
                          onChanged: (_) => setState(() {}),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: 'What was it for? (optional)',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            prefixIcon: Icon(
                              Icons.edit_note_rounded,
                              color: Colors.white.withValues(alpha: 0.68),
                              size: 20,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [100, 500, 1000, 5000]
                              .map(
                                (amt) => GestureDetector(
                                  onTap: () => setState(
                                    () =>
                                        _amountController.text = amt.toString(),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '₹$amt',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Live preview
                  if (_selectedCategory >= 0 &&
                      _amountController.text.isNotEmpty) ...[
                    PremiumSurfaceCard(
                      variant: PremiumSurfaceVariant.dashboard,
                      padding: const EdgeInsets.all(16),
                      radius: 24,
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: selectedCategory!.color.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                selectedCategory.emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _notesController.text.isNotEmpty
                                      ? _notesController.text
                                      : selectedCategory.name,
                                  style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Preview entry · ${selectedCategory.name}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₹${_amountController.text}',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Categories
                  Text(
                    'SELECT CATEGORY',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PremiumSurfaceCard(
                    variant: PremiumSurfaceVariant.neutral,
                    padding: const EdgeInsets.all(16),
                    radius: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose the spend bucket that should carry this entry.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.9,
                              ),
                          itemCount: _showAllCategories
                              ? defaultCategories.length
                              : 8,
                          itemBuilder: (context, index) {
                            final cat = defaultCategories[index];
                            final isSelected = _selectedCategory == index;

                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedCategory = index),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? cat.color.withValues(alpha: 0.12)
                                      : colors.surface.withValues(alpha: 0.66),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isSelected
                                        ? cat.color.withValues(alpha: 0.36)
                                        : colors.outlineVariant.withValues(
                                            alpha: 0.12,
                                          ),
                                    width: isSelected ? 1.4 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      cat.emoji,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      cat.name,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? cat.color
                                            : colors.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (!_showAllCategories && defaultCategories.length > 8)
                    Center(
                      child: GestureDetector(
                        onTap: () => setState(() => _showAllCategories = true),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'View all ${defaultCategories.length} categories',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Sticky save button
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(context).viewInsets.bottom > 0
                  ? 12
                  : MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.92),
            ),
            child: GestureDetector(
              onTap: _isSaving ? null : _saveTransaction,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.primaryContainer],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save Expense',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
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
