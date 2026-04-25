/**
 * VisitReportTriggerHandler
 *
 * Maintains roll-up fields on Account (Physician__c / Hospital__c) and Contact (Prescriber__c):
 *   Account: Total_Visits__c, Last_Visit_Date__c, Relationship_Score__c, Total_Expenses__c
 *   Contact: Total_Visits__c, Last_Visit_Date__c, Relationship_Score__c, Total_Expenses__c
 *
 * Bulkified: one SOQL per object type and one DML per object type per trigger invocation.
 */
public with sharing class VisitReportTriggerHandler {

    // ── Entry points ──────────────────────────────────────────────────────────

    public void onAfterInsert(List<Visit_Report__c> newRecords) {
        updateAccountStats(collectAccountIds(newRecords, null));
        updateContactStats(collectContactIds(newRecords, null));
        updateHospitalExpenses(collectHospitalIds(newRecords, null));
    }

    public void onAfterUpdate(List<Visit_Report__c> newRecords, Map<Id, Visit_Report__c> oldMap) {
        Set<Id> accountIds = collectAccountIds(newRecords, null);
        Set<Id> contactIds = collectContactIds(newRecords, null);
        Set<Id> hospitalIds = collectHospitalIds(newRecords, null);

        for (Visit_Report__c vr : newRecords) {
            Visit_Report__c old = oldMap.get(vr.Id);
            if (vr.Physician__c != old.Physician__c && old.Physician__c != null) {
                accountIds.add(old.Physician__c);
            }
            if (vr.Prescriber__c != old.Prescriber__c && old.Prescriber__c != null) {
                contactIds.add(old.Prescriber__c);
            }
            if (vr.Hospital__c != old.Hospital__c && old.Hospital__c != null) {
                hospitalIds.add(old.Hospital__c);
            }
        }

        updateAccountStats(accountIds);
        updateContactStats(contactIds);
        updateHospitalExpenses(hospitalIds);
    }

    public void onAfterDelete(List<Visit_Report__c> oldRecords) {
        updateAccountStats(collectAccountIds(oldRecords, null));
        updateContactStats(collectContactIds(oldRecords, null));
        updateHospitalExpenses(collectHospitalIds(oldRecords, null));
    }

    public void onAfterUndelete(List<Visit_Report__c> newRecords) {
        updateAccountStats(collectAccountIds(newRecords, null));
        updateContactStats(collectContactIds(newRecords, null));
        updateHospitalExpenses(collectHospitalIds(newRecords, null));
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private Set<Id> collectAccountIds(List<Visit_Report__c> records, Map<Id, Visit_Report__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Visit_Report__c vr : records) {
            if (vr.Physician__c != null) ids.add(vr.Physician__c);
        }
        return ids;
    }

    private Set<Id> collectContactIds(List<Visit_Report__c> records, Map<Id, Visit_Report__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Visit_Report__c vr : records) {
            if (vr.Prescriber__c != null) ids.add(vr.Prescriber__c);
        }
        return ids;
    }

    private Set<Id> collectHospitalIds(List<Visit_Report__c> records, Map<Id, Visit_Report__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Visit_Report__c vr : records) {
            if (vr.Hospital__c != null) ids.add(vr.Hospital__c);
        }
        return ids;
    }

    private void updateAccountStats(Set<Id> accountIds) {
        if (accountIds.isEmpty()) return;

        Map<Id, List<Visit_Report__c>> visitsByAccount = new Map<Id, List<Visit_Report__c>>();
        for (Id accId : accountIds) {
            visitsByAccount.put(accId, new List<Visit_Report__c>());
        }

        for (Visit_Report__c vr : [
            SELECT Id, Physician__c, Visit_Date__c, Engagement_Score__c
            FROM   Visit_Report__c
            WHERE  Physician__c IN :accountIds
            ORDER  BY Visit_Date__c DESC NULLS LAST
        ]) {
            visitsByAccount.get(vr.Physician__c).add(vr);
        }

        List<Account> toUpdate = new List<Account>();
        for (Id accId : accountIds) {
            List<Visit_Report__c> visits = visitsByAccount.get(accId);
            Account acc = new Account(Id = accId);
            acc.Total_Visits__c = visits.size();
            acc.Last_Visit_Date__c = visits.isEmpty() ? null : visits[0].Visit_Date__c;

            Decimal scoreSum = 0;
            Integer scoreCount = 0;
            for (Integer i = 0; i < Math.min(10, visits.size()); i++) {
                if (visits[i].Engagement_Score__c != null) {
                    scoreSum  += visits[i].Engagement_Score__c;
                    scoreCount++;
                }
            }
            acc.Relationship_Score__c = scoreCount > 0 ? (scoreSum / scoreCount).setScale(1) : null;
            toUpdate.add(acc);
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }

    private void updateContactStats(Set<Id> contactIds) {
        if (contactIds.isEmpty()) return;

        Map<Id, List<Visit_Report__c>> visitsByContact = new Map<Id, List<Visit_Report__c>>();
        for (Id conId : contactIds) {
            visitsByContact.put(conId, new List<Visit_Report__c>());
        }

        for (Visit_Report__c vr : [
            SELECT Id, Prescriber__c, Visit_Date__c, Engagement_Score__c, Total_Expense_Amount__c
            FROM   Visit_Report__c
            WHERE  Prescriber__c IN :contactIds
            ORDER  BY Visit_Date__c DESC NULLS LAST
        ]) {
            visitsByContact.get(vr.Prescriber__c).add(vr);
        }

        List<Contact> toUpdate = new List<Contact>();
        for (Id conId : contactIds) {
            List<Visit_Report__c> visits = visitsByContact.get(conId);
            Contact con = new Contact(Id = conId);
            con.Total_Visits__c    = visits.size();
            con.Last_Visit_Date__c = visits.isEmpty() ? null : visits[0].Visit_Date__c;

            Decimal scoreSum    = 0;
            Integer scoreCount  = 0;
            Decimal expenseSum  = 0;
            for (Integer i = 0; i < visits.size(); i++) {
                if (i < 10 && visits[i].Engagement_Score__c != null) {
                    scoreSum  += visits[i].Engagement_Score__c;
                    scoreCount++;
                }
                if (visits[i].Total_Expense_Amount__c != null) {
                    expenseSum += visits[i].Total_Expense_Amount__c;
                }
            }
            con.Relationship_Score__c = scoreCount > 0 ? (scoreSum / scoreCount).setScale(1) : null;
            con.Total_Expenses__c     = expenseSum;
            toUpdate.add(con);
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }

    private void updateHospitalExpenses(Set<Id> hospitalIds) {
        if (hospitalIds.isEmpty()) return;

        Map<Id, Decimal> expenseByHospital = new Map<Id, Decimal>();
        for (Id hId : hospitalIds) {
            expenseByHospital.put(hId, 0);
        }

        for (AggregateResult ar : [
            SELECT Hospital__c accId, SUM(Total_Expense_Amount__c) total
            FROM   Visit_Report__c
            WHERE  Hospital__c IN :hospitalIds
            GROUP  BY Hospital__c
        ]) {
            Id hId = (Id) ar.get('accId');
            Decimal total = (Decimal) ar.get('total');
            expenseByHospital.put(hId, total != null ? total : 0);
        }

        List<Account> toUpdate = new List<Account>();
        for (Id hId : hospitalIds) {
            toUpdate.add(new Account(Id = hId, Total_Expenses__c = expenseByHospital.get(hId)));
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }
}
