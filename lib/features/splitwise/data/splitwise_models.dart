/// A group for splitting expenses (trips, roommates, etc.)
class SplitGroup {
  final String? id;
  final String name;
  final String type; // 'trip', 'roommates', 'couple', 'friends', 'other'
  final String emoji;
  final String createdBy;
  final String? createdAt;

  SplitGroup({
    this.id,
    required this.name,
    required this.type,
    required this.emoji,
    required this.createdBy,
    this.createdAt,
  });

  Map<String, dynamic> toInsertMap() => {
    'name': name,
    'type': type,
    'emoji': emoji,
    'created_by': createdBy,
  };

  factory SplitGroup.fromMap(Map<String, dynamic> map) => SplitGroup(
    id: map['id']?.toString(),
    name: map['name'] as String,
    type: map['type'] as String? ?? 'other',
    emoji: map['emoji'] as String? ?? '👥',
    createdBy: map['created_by'] as String,
    createdAt: map['created_at'] as String?,
  );
}

/// A member of a group
class GroupMember {
  final String? id;
  final String groupId;
  final String name;
  final String? phone;
  final String? userId; // null if not a registered user
  final bool isCurrentUser;

  GroupMember({
    this.id,
    required this.groupId,
    required this.name,
    this.phone,
    this.userId,
    this.isCurrentUser = false,
  });

  Map<String, dynamic> toInsertMap() => {
    'group_id': groupId,
    'name': name,
    'phone': phone,
    'user_id': userId,
  };

  factory GroupMember.fromMap(
    Map<String, dynamic> map, {
    String? currentUserId,
  }) => GroupMember(
    id: map['id']?.toString(),
    groupId: map['group_id'] as String,
    name: map['name'] as String,
    phone: map['phone'] as String?,
    userId: map['user_id'] as String?,
    isCurrentUser: map['user_id'] == currentUserId,
  );

  GroupMember copyWith({
    String? name,
    String? phone,
    String? userId,
    bool? isCurrentUser,
  }) => GroupMember(
    id: id,
    groupId: groupId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    userId: userId ?? this.userId,
    isCurrentUser: isCurrentUser ?? this.isCurrentUser,
  );
}

/// An expense to be split among group members
class SplitExpense {
  final String? id;
  final String groupId;
  final String description;
  final double amount;
  final String paidBy; // member_id of who paid
  final String splitType; // 'equal', 'exact', 'percentage', 'shares'
  final String? category;
  final String? createdAt;

  SplitExpense({
    this.id,
    required this.groupId,
    required this.description,
    required this.amount,
    required this.paidBy,
    this.splitType = 'equal',
    this.category,
    this.createdAt,
  });

  Map<String, dynamic> toInsertMap() => {
    'group_id': groupId,
    'description': description,
    'amount': amount,
    'paid_by': paidBy,
    'split_type': splitType,
    'category': category,
  };

  factory SplitExpense.fromMap(Map<String, dynamic> map) => SplitExpense(
    id: map['id']?.toString(),
    groupId: map['group_id'] as String,
    description: map['description'] as String,
    amount: (map['amount'] as num).toDouble(),
    paidBy: map['paid_by'] as String,
    splitType: map['split_type'] as String? ?? 'equal',
    category: map['category'] as String?,
    createdAt: map['created_at'] as String?,
  );
}

/// How an expense is split per participant
class ExpenseSplit {
  final String? id;
  final String expenseId;
  final String memberId;
  final double amount; // how much this person owes

  ExpenseSplit({
    this.id,
    required this.expenseId,
    required this.memberId,
    required this.amount,
  });

  Map<String, dynamic> toInsertMap() => {
    'expense_id': expenseId,
    'member_id': memberId,
    'amount': amount,
  };

  factory ExpenseSplit.fromMap(Map<String, dynamic> map) => ExpenseSplit(
    id: map['id']?.toString(),
    expenseId: map['expense_id'] as String,
    memberId: map['member_id'] as String,
    amount: (map['amount'] as num).toDouble(),
  );
}

/// A settlement payment between two members
class Settlement {
  final String? id;
  final String groupId;
  final String fromMember; // who paid
  final String toMember; // who received
  final double amount;
  final String method; // 'cash', 'upi', 'bank'
  final String? createdAt;

  Settlement({
    this.id,
    required this.groupId,
    required this.fromMember,
    required this.toMember,
    required this.amount,
    this.method = 'cash',
    this.createdAt,
  });

  Map<String, dynamic> toInsertMap() => {
    'group_id': groupId,
    'from_member': fromMember,
    'to_member': toMember,
    'amount': amount,
    'method': method,
  };

  factory Settlement.fromMap(Map<String, dynamic> map) => Settlement(
    id: map['id']?.toString(),
    groupId: map['group_id'] as String,
    fromMember: map['from_member'] as String,
    toMember: map['to_member'] as String,
    amount: (map['amount'] as num).toDouble(),
    method: map['method'] as String? ?? 'cash',
    createdAt: map['created_at'] as String?,
  );
}

/// Activity log entry — tracks who created/edited/deleted expenses & settlements
class ActivityEntry {
  final String? id;
  final String groupId;
  final String userId;
  final String action; // 'added', 'edited', 'deleted', 'settled'
  final String description; // "Dinner" or "Settlement"
  final String? details; // "Amount: ₹1000 → ₹1200" or "Paid ₹500 via UPI"
  final String? createdAt;

  ActivityEntry({
    this.id,
    required this.groupId,
    required this.userId,
    required this.action,
    required this.description,
    this.details,
    this.createdAt,
  });

  Map<String, dynamic> toInsertMap() => {
    'group_id': groupId,
    'user_id': userId,
    'action': action,
    'description': description,
    'details': details,
  };

  factory ActivityEntry.fromMap(Map<String, dynamic> map) => ActivityEntry(
    id: map['id']?.toString(),
    groupId: map['group_id'] as String,
    userId: map['user_id'] as String,
    action: map['action'] as String,
    description: map['description'] as String,
    details: map['details'] as String?,
    createdAt: map['created_at'] as String?,
  );
}

// ---------------------------------------------------------------------------
// Debt simplification algorithm
// ---------------------------------------------------------------------------

class DebtEntry {
  final String fromMemberId;
  final String toMemberId;
  final double amount;

  DebtEntry({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
  });
}

/// Calculate simplified debts from expenses and settlements
/// Returns minimum number of transactions to settle all debts
List<DebtEntry> simplifyDebts(
  List<SplitExpense> expenses,
  List<ExpenseSplit> splits,
  List<Settlement> settlements,
) {
  // Calculate net balance for each member
  // Positive = owed money, Negative = owes money
  final balances = <String, double>{};

  // From expenses: payer gets +amount, each split participant gets -their_share
  for (final expense in expenses) {
    balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) + expense.amount;
  }
  for (final split in splits) {
    balances[split.memberId] = (balances[split.memberId] ?? 0) - split.amount;
  }

  // From settlements: debtor (fromMember) paid money → balance goes up (less negative)
  // creditor (toMember) received money → balance goes down (less positive)
  for (final s in settlements) {
    balances[s.fromMember] = (balances[s.fromMember] ?? 0) + s.amount;
    balances[s.toMember] = (balances[s.toMember] ?? 0) - s.amount;
  }

  // Separate into creditors (positive) and debtors (negative)
  // Use 0.01 threshold (1 paisa) — anything larger is real money
  const epsilon = 0.01;
  final creditors = <MapEntry<String, double>>[];
  final debtors = <MapEntry<String, double>>[];

  for (final entry in balances.entries) {
    if (entry.value > epsilon) {
      creditors.add(entry);
    } else if (entry.value < -epsilon) {
      debtors.add(MapEntry(entry.key, -entry.value)); // make positive
    }
  }

  // Sort by amount descending for greedy matching
  creditors.sort((a, b) => b.value.compareTo(a.value));
  debtors.sort((a, b) => b.value.compareTo(a.value));

  // Greedy algorithm: match largest debtor with largest creditor
  final result = <DebtEntry>[];
  final creds = creditors.map((e) => _MutableBalance(e.key, e.value)).toList();
  final debts = debtors.map((e) => _MutableBalance(e.key, e.value)).toList();

  int ci = 0, di = 0;
  while (ci < creds.length && di < debts.length) {
    final transfer = creds[ci].amount < debts[di].amount
        ? creds[ci].amount
        : debts[di].amount;
    if (transfer > epsilon) {
      result.add(
        DebtEntry(
          fromMemberId: debts[di].id,
          toMemberId: creds[ci].id,
          amount: double.parse(transfer.toStringAsFixed(2)),
        ),
      );
    }
    creds[ci].amount -= transfer;
    debts[di].amount -= transfer;
    if (creds[ci].amount < epsilon) ci++;
    if (debts[di].amount < epsilon) di++;
  }

  return result;
}

class _MutableBalance {
  final String id;
  double amount;
  _MutableBalance(this.id, this.amount);
}
