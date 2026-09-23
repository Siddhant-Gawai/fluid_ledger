import 'package:fluid_ledger/features/splitwise/data/splitwise_realtime_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SplitwiseRealtimeMapper', () {
    test('maps split group changes to a group refresh event', () {
      final invalidation = SplitwiseRealtimeMapper.fromTableChange(
        table: 'split_groups',
        newRecord: {'id': 'group_1'},
        oldRecord: const {},
      );

      expect(invalidation.groupsChanged, isTrue);
      expect(invalidation.groupIds, {'group_1'});
    });

    test('maps group member changes to the owning group', () {
      final invalidation = SplitwiseRealtimeMapper.fromTableChange(
        table: 'group_members',
        newRecord: {'group_id': 'group_2'},
        oldRecord: const {},
      );

      expect(invalidation.groupsChanged, isTrue);
      expect(invalidation.groupIds, {'group_2'});
    });

    test(
      'maps expense and settlement changes without forcing full group reload',
      () {
        final expenseInvalidation = SplitwiseRealtimeMapper.fromTableChange(
          table: 'split_expenses',
          newRecord: {'group_id': 'group_3'},
          oldRecord: const {},
        );
        final settlementInvalidation = SplitwiseRealtimeMapper.fromTableChange(
          table: 'settlements',
          newRecord: const {},
          oldRecord: {'group_id': 'group_4'},
        );

        expect(expenseInvalidation.groupsChanged, isFalse);
        expect(expenseInvalidation.groupIds, {'group_3'});
        expect(settlementInvalidation.groupsChanged, isFalse);
        expect(settlementInvalidation.groupIds, {'group_4'});
      },
    );
  });
}
