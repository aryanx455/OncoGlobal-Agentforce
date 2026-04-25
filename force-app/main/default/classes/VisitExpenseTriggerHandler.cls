public with sharing class VisitExpenseTriggerHandler {

    private static Decimal policyLimit {
        get {
            if (policyLimit == null) {
                VisitPolicy__mdt policy = VisitPolicy__mdt.getInstance('Default_Policy');
                policyLimit = (policy != null && policy.Per_Visit_Limit__c != null)
                    ? policy.Per_Visit_Limit__c
                    : 150;
            }
            return policyLimit;
        }
        set;
    }

    public void setPolicyFlag(List<Expense__c> expenses) {
        for (Expense__c exp : expenses) {
            exp.Policy_Flag__c = (exp.Amount__c != null && exp.Amount__c > policyLimit);
        }
    }

    public void updateVisitReportRollup(List<Expense__c> newList, List<Expense__c> oldList) {
        Set<Id> reportIds = new Set<Id>();

        if (newList != null) {
            for (Expense__c exp : newList) {
                if (exp.Visit_Report__c != null) reportIds.add(exp.Visit_Report__c);
            }
        }
        if (oldList != null) {
            for (Expense__c exp : oldList) {
                if (exp.Visit_Report__c != null) reportIds.add(exp.Visit_Report__c);
            }
        }

        if (reportIds.isEmpty()) return;

        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        for (Id rid : reportIds) totals.put(rid, 0);

        for (AggregateResult ar : [
            SELECT Visit_Report__c vrId, SUM(Amount__c) total
            FROM Expense__c
            WHERE Visit_Report__c IN :reportIds
            GROUP BY Visit_Report__c
        ]) {
            totals.put((Id) ar.get('vrId'), (Decimal) ar.get('total'));
        }

        List<Visit_Report__c> reportsToUpdate = new List<Visit_Report__c>();
        for (Id rid : reportIds) {
            reportsToUpdate.add(new Visit_Report__c(
                Id = rid,
                Total_Expense_Amount__c = totals.get(rid)
            ));
        }
        update reportsToUpdate;
    }
}
