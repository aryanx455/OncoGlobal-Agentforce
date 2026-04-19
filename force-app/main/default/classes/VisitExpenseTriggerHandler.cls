/**
 * VisitExpenseTriggerHandler
 *
 * Before insert/update: sets Policy_Flag__c to true when Amount__c exceeds
 * the per-visit limit defined in VisitPolicy__mdt.Default_Policy (FR-EXP-003, BR-007).
 *
 * The limit is read from Custom Metadata so Finance Admin can adjust it in
 * Setup > Custom Metadata Types without a code deployment.
 */
public with sharing class VisitExpenseTriggerHandler {

    // Cache the policy limit for the lifetime of this transaction
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

    public void setPolicyFlag(List<Visit_Expense__c> expenses) {
        for (Visit_Expense__c exp : expenses) {
            exp.Policy_Flag__c = (exp.Amount__c != null && exp.Amount__c > policyLimit);
        }
    }
}
