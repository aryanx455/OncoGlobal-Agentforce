/**
 * LogExpenseAction
 * @InvocableMethod — called by Agentforce to log one or more expenses
 * mentioned in the post-visit voice transcript.
 *
 * Can work with a Visit Report ID (preferred) OR with a physician name +
 * visit date to look up or create the associated visit report automatically.
 */
public without sharing class LogExpenseAction {

    // ─── INPUT / OUTPUT ────────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(required=true label='Amount'
            description='Expense amount in Indian Rupees (e.g. 450 for a lunch costing Rs. 450).')
        public Decimal amount;

        @InvocableVariable(required=true label='Category'
            description='Expense category. Must be one of: Meal, Travel, Accommodation, Samples, CME / Event, Other.')
        public String category;

        @InvocableVariable(label='Visit Report ID'
            description='Salesforce ID of the Visit Report to link this expense to. Optional — if not provided, the agent will look up today\'s visit report for the named physician.')
        public Id visitReportId;

        @InvocableVariable(label='Physician Name'
            description='Name of the physician as spoken by the rep (e.g. "Dr. Reddy"). Used to find today\'s visit report when Visit Report ID is not provided.')
        public String physicianName;

        @InvocableVariable(label='Hospital or Facility Name'
            description='Name of the hospital or clinic (e.g. "HCG Bangalore"). Helps find the correct visit report.')
        public String hospitalName;

        @InvocableVariable(label='Visit Date (defaults to today)')
        public Date visitDate;

        @InvocableVariable(label='Notes'
            description='Free-text notes about the expense (e.g. "lunch with Dr. Reddy at HCG Bangalore").')
        public String notes;

        @InvocableVariable(label='Receipt URL')
        public String receiptUrl;
    }

    public class Result {
        @InvocableVariable(label='Expense ID')
        public Id expenseId;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Policy Flagged'
            description='True if the expense exceeds the Rs.150 policy limit.')
        public Boolean policyFlagged;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Visit Report ID (resolved)')
        public Id resolvedVisitReportId;
    }

    // ─── INVOCABLE ENTRY POINT ─────────────────────────────────────────────────

    @InvocableMethod(
        label='Log Visit Expense'
        description='Creates a Visit_Expense__c record linked to a Visit Report. Amount and Category are required. Accepts physician name (e.g. "Dr. Reddy") and hospital name (e.g. "HCG Bangalore") to find the visit report — no Salesforce IDs needed. Policy flag is auto-set by trigger.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Visit_Expense__c> expensesToInsert = new List<Visit_Expense__c>();
        List<Result> results = new List<Result>();
        List<Integer> validIndexes = new List<Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = new Result();
            res.success = false;

            if (req.amount == null || req.amount <= 0) {
                res.errorMessage = 'Amount must be greater than 0.';
                results.add(res);
                continue;
            }
            if (String.isBlank(req.category)) {
                res.errorMessage = 'Category is required.';
                results.add(res);
                continue;
            }

            // ── Resolve visit report ─────────────────────────────────────────
            Id resolvedVisitReportId = req.visitReportId;

            if (resolvedVisitReportId == null) {
                resolvedVisitReportId = findOrCreateVisitReport(req.physicianName, req.hospitalName, req.visitDate);
            }

            res.resolvedVisitReportId = resolvedVisitReportId;

            Visit_Expense__c exp = new Visit_Expense__c(
                Visit_Report__c = resolvedVisitReportId,
                Amount__c       = req.amount,
                Category__c     = req.category,
                Notes__c        = req.notes,
                Receipt_URL__c  = req.receiptUrl
            );

            expensesToInsert.add(exp);
            validIndexes.add(i);
            results.add(res);
        }

        if (!expensesToInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(expensesToInsert, false);

            for (Integer j = 0; j < saveResults.size(); j++) {
                Database.SaveResult sr = saveResults[j];
                Result res = results[validIndexes[j]];
                if (sr.isSuccess()) {
                    res.success = true;
                    res.expenseId = sr.getId();
                    // Re-query to get trigger-set Policy_Flag__c
                    try {
                        res.policyFlagged = [
                            SELECT Policy_Flag__c
                            FROM Visit_Expense__c
                            WHERE Id = :sr.getId()
                            LIMIT 1
                        ].Policy_Flag__c;
                    } catch (Exception e) {
                        res.policyFlagged = false;
                    }
                } else {
                    res.success = false;
                    res.errorMessage = sr.getErrors()[0].getMessage();
                }
            }
        }

        return results;
    }

    // ─── HELPERS ──────────────────────────────────────────────────────────────

    /**
     * Find today's visit report for a given physician (by name), or create a
     * minimal one so the expense can be linked.
     */
    @TestVisible
    private static Id findOrCreateVisitReport(String physicianName, String hospitalName, Date visitDate) {
        Date targetDate = visitDate != null ? visitDate : Date.today();

        // Try to find an existing visit report for this physician today
        if (String.isNotBlank(physicianName)) {
            String nameWildcard = '%' + physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim() + '%';
            List<Visit_Report__c> existing = [
                SELECT Id
                FROM Visit_Report__c
                WHERE Visit_Date__c = :targetDate
                AND Physician__r.Name LIKE :nameWildcard
                AND OwnerId = :UserInfo.getUserId()
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }
        }

        // Look up the physician account
        Id physicianId = null;
        if (String.isNotBlank(physicianName)) {
            String nameWildcard = '%' + physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim() + '%';
            List<Account> accounts = [
                SELECT Id FROM Account
                WHERE Name LIKE :nameWildcard
                ORDER BY LastModifiedDate DESC LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                physicianId = accounts[0].Id;
            }
        }

        // Create a minimal visit report
        String notes = 'Auto-created by LogExpenseAction.';
        if (String.isNotBlank(hospitalName)) notes += ' Hospital: ' + hospitalName;

        Visit_Report__c vr = new Visit_Report__c(
            Physician__c        = physicianId,
            Rep__c              = UserInfo.getUserId(),
            Visit_Date__c       = targetDate,
            Visit_Outcome__c    = 'Neutral',
            Visit_Type__c       = 'In-Person Clinic',
            Voice_Transcript__c = notes
        );
        try {
            insert vr;
            return vr.Id;
        } catch (Exception e) {
            return null;
        }
    }
}
