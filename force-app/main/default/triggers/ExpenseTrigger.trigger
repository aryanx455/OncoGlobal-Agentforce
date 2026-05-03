trigger ExpenseTrigger on Expense__c (before insert, before update, after insert, after update, after delete) {
    VisitExpenseTriggerHandler handler = new VisitExpenseTriggerHandler();
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            handler.setPolicyFlag(Trigger.new);
        }
    }
    if (Trigger.isAfter) {
        handler.updateVisitReportRollup(
            Trigger.isDelete ? null : Trigger.new,
            Trigger.isInsert ? null : Trigger.old
        );
    }
}
