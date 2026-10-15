import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import '../models/session_model.dart';
import '../utils/helpers.dart';

/// Prompts for a single session expense (category + amount + optional note).
/// Returns null if cancelled or the amount is blank/invalid. Shared by the
/// live recorder and the manual log form so they stay consistent.
Future<ExpenseEvent?> showExpenseDialog(
  BuildContext context,
  String currency, {
  ExpenseEvent? existing,
}) async {
  final amountCtrl = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '');
  final noteCtrl = TextEditingController(text: existing?.note ?? '');
  String category = existing?.category ?? kExpenseCategoryIds.first;
  final l10n = context.l10n;

  final result = await showDialog<ExpenseEvent>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(existing == null
            ? l10n.expenseDialogAddTitle
            : l10n.expenseDialogEditTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: InputDecoration(
                  labelText: l10n.expenseDialogCategory, isDense: true),
              items: [
                for (final id in kExpenseCategoryIds)
                  DropdownMenuItem(
                      value: id, child: Text(expenseCategoryLabel(l10n, id))),
              ],
              onChanged: (v) => setLocal(() => category = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '${currencySymbol(currency)} ',
                labelText: l10n.expenseDialogAmount,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: l10n.expenseDialogNote, isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () {
              final amt = double.tryParse(amountCtrl.text.trim());
              if (amt == null || amt <= 0) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(
                ctx,
                ExpenseEvent(
                  amount: amt,
                  category: category,
                  note: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                  ts: existing?.ts ?? DateTime.now(),
                ),
              );
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    ),
  );
  amountCtrl.dispose();
  noteCtrl.dispose();
  return result;
}
