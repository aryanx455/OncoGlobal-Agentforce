trigger VisitReportTrigger on Visit_Report__c (
    after insert,
    after update,
    after delete,
    after undelete
) {
    VisitReportTriggerHandler handler = new VisitReportTriggerHandler();
    if (Trigger.isAfter) {
        if (Trigger.isInsert)   handler.onAfterInsert(Trigger.new);
        if (Trigger.isUpdate)   handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
        if (Trigger.isDelete)   handler.onAfterDelete(Trigger.old);
        if (Trigger.isUndelete) handler.onAfterUndelete(Trigger.new);
    }
}
