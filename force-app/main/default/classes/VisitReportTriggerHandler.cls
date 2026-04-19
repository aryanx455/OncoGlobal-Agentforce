/**
 * VisitReportTriggerHandler
 *
 * Maintains three roll-up-style fields on Account that cannot use native
 * Roll-Up Summary because the Account fields already exist as Number/Date:
 *   - Total_Visits__c        : COUNT of all Visit Reports (BR-004)
 *   - Last_Visit_Date__c     : MAX Visit_Date__c across all Visit Reports (BR-005)
 *   - Relationship_Score__c  : Rolling average of last 10 Engagement_Score__c values (BR-003)
 *
 * Bulkified: one SOQL and one DML per trigger invocation regardless of batch size.
 */
public with sharing class VisitReportTriggerHandler {

    // ── Entry points ──────────────────────────────────────────────────────────

    public void onAfterInsert(List<Visit_Report__c> newRecords) {
        updateAccountStats(collectAccountIds(newRecords, null));
    }

    public void onAfterUpdate(List<Visit_Report__c> newRecords, Map<Id, Visit_Report__c> oldMap) {
        Set<Id> accountIds = collectAccountIds(newRecords, null);
        // If Physician changed, also recalculate the old physician's account
        for (Visit_Report__c vr : newRecords) {
            Visit_Report__c old = oldMap.get(vr.Id);
            if (vr.Physician__c != old.Physician__c && old.Physician__c != null) {
                accountIds.add(old.Physician__c);
            }
        }
        updateAccountStats(accountIds);
    }

    public void onAfterDelete(List<Visit_Report__c> oldRecords) {
        updateAccountStats(collectAccountIds(oldRecords, null));
    }

    public void onAfterUndelete(List<Visit_Report__c> newRecords) {
        updateAccountStats(collectAccountIds(newRecords, null));
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private Set<Id> collectAccountIds(List<Visit_Report__c> records, Map<Id, Visit_Report__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Visit_Report__c vr : records) {
            if (vr.Physician__c != null) {
                ids.add(vr.Physician__c);
            }
        }
        return ids;
    }

    private void updateAccountStats(Set<Id> accountIds) {
        if (accountIds.isEmpty()) return;

        // Single SOQL — fetch all visit reports for affected accounts ordered newest first
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

        // Calculate stats and build update list
        List<Account> toUpdate = new List<Account>();
        for (Id accId : accountIds) {
            List<Visit_Report__c> visits = visitsByAccount.get(accId);

            Account acc = new Account(Id = accId);
            acc.Total_Visits__c = visits.size();
            acc.Last_Visit_Date__c = visits.isEmpty() ? null : visits[0].Visit_Date__c;

            // Rolling average of last 10 scored visits
            Decimal scoreSum   = 0;
            Integer scoreCount = 0;
            for (Integer i = 0; i < Math.min(10, visits.size()); i++) {
                if (visits[i].Engagement_Score__c != null) {
                    scoreSum  += visits[i].Engagement_Score__c;
                    scoreCount++;
                }
            }
            acc.Relationship_Score__c = scoreCount > 0
                ? (scoreSum / scoreCount).setScale(1)
                : null;

            toUpdate.add(acc);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
