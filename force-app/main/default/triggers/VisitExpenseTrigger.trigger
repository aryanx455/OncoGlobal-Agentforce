trigger VisitExpenseTrigger on Visit_Expense__c (before insert, before update) {
    VisitExpenseTriggerHandler handler = new VisitExpenseTriggerHandler();
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            handler.setPolicyFlag(Trigger.new);
        }
    }
}
