/**
 * LogExpenseAction
 * Creates Visit_Expense__c records. Accepts total bill amount as-is.
 * GST fields (rate, SGST, CGST, invoice number) are optional — only stored
 * when the rep explicitly provides them from the receipt.
 */
public without sharing class LogExpenseAction {

    // ─── INPUT / OUTPUT ────────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(required=true label='Amount'
            description='Total expense amount in Indian Rupees as stated by the rep (e.g. 450 for Rs. 450 ka bill). Do not calculate or modify — use exactly what the rep says.')
        public Decimal amount;

        @InvocableVariable(required=true label='Category'
            description='Expense category. Must be exactly one of: Meal, Travel, Accommodation, Samples, CME / Event, Other.')
        public String category;

        @InvocableVariable(label='Visit Report ID'
            description='Salesforce ID of the Visit Report to link this expense to. Optional — action finds today\'s visit report for the named physician if not provided.')
        public Id visitReportId;

        @InvocableVariable(label='Physician Name'
            description='Name of the physician (e.g. "Dr. Reddy"). Used to find today\'s visit report.')
        public String physicianName;

        @InvocableVariable(label='Hospital or Facility Name'
            description='Name of the hospital or clinic. Helps find the correct visit report.')
        public String hospitalName;

        @InvocableVariable(label='Visit Date (defaults to today)')
        public Date visitDate;

        @InvocableVariable(label='Notes'
            description='Free-text notes about the expense (e.g. "Lunch with Dr. Reddy at HCG Bangalore").')
        public String notes;

        @InvocableVariable(label='Receipt URL')
        public String receiptUrl;

        @InvocableVariable(label='GST Rate (%)'
            description='GST percentage from the receipt — only when rep explicitly states it (e.g. "bill mein 5% GST tha"). Leave blank otherwise.')
        public Decimal gstRate;

        @InvocableVariable(label='SGST Amount (Rs.)'
            description='SGST amount from receipt — only when rep explicitly reads it out. Leave blank otherwise.')
        public Decimal sgstAmount;

        @InvocableVariable(label='CGST Amount (Rs.)'
            description='CGST amount from receipt — only when rep explicitly reads it out. Leave blank otherwise.')
        public Decimal cgstAmount;

        @InvocableVariable(label='GST Invoice Number'
            description='Invoice/bill number from the receipt, if rep provides it.')
        public String gstInvoiceNumber;
    }

    public class Result {
        @InvocableVariable(label='Expense ID')
        public Id expenseId;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Policy Flagged'
            description='True if the expense exceeds the Rs.150 company policy limit.')
        public Boolean policyFlagged;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Visit Report ID (resolved)')
        public Id resolvedVisitReportId;
    }

    // ─── INVOCABLE ENTRY POINT ─────────────────────────────────────────────────

    @InvocableMethod(
        label='Log Visit Expense'
        description='Creates a Visit_Expense__c record. Required: Amount (total bill in Rs.) and Category (Meal/Travel/Accommodation/Samples/CME Event/Other). Accepts Physician Name to auto-link to today\'s visit report. Auto-flags amounts over Rs.150. GST fields optional — only stored if rep explicitly provides them.'
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
                Visit_Report__c       = resolvedVisitReportId,
                Amount__c             = req.amount,
                Category__c           = req.category,
                Notes__c              = req.notes,
                Receipt_URL__c        = req.receiptUrl,
                GST_Rate__c           = req.gstRate,
                SGST_Amount__c        = req.sgstAmount,
                CGST_Amount__c        = req.cgstAmount,
                GST_Invoice_Number__c = req.gstInvoiceNumber
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
                    res.success   = true;
                    res.expenseId = sr.getId();
                    try {
                        res.policyFlagged = [
                            SELECT Policy_Flag__c FROM Visit_Expense__c
                            WHERE Id = :sr.getId() LIMIT 1
                        ].Policy_Flag__c;
                    } catch (Exception e) {
                        res.policyFlagged = false;
                    }
                } else {
                    res.success      = false;
                    res.errorMessage = sr.getErrors()[0].getMessage();
                }
            }
        }

        return results;
    }

    // ─── HELPERS ──────────────────────────────────────────────────────────────

    @TestVisible
    private static Id findOrCreateVisitReport(String physicianName, String hospitalName, Date visitDate) {
        Date targetDate = visitDate != null ? visitDate : Date.today();

        if (String.isNotBlank(physicianName)) {
            String nameWildcard = '%' + physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim() + '%';

            List<Visit_Report__c> byContact = [
                SELECT Id FROM Visit_Report__c
                WHERE Visit_Date__c = :targetDate
                AND Prescriber__r.Name LIKE :nameWildcard
                AND OwnerId = :UserInfo.getUserId()
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!byContact.isEmpty()) return byContact[0].Id;

            List<Visit_Report__c> byAccount = [
                SELECT Id FROM Visit_Report__c
                WHERE Visit_Date__c = :targetDate
                AND Physician__r.Name LIKE :nameWildcard
                AND OwnerId = :UserInfo.getUserId()
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!byAccount.isEmpty()) return byAccount[0].Id;
        }

        Id physicianId = null;
        if (String.isNotBlank(physicianName)) {
            String nameWildcard = '%' + physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim() + '%';
            List<Account> accounts = [
                SELECT Id FROM Account WHERE Name LIKE :nameWildcard
                ORDER BY LastModifiedDate DESC LIMIT 1
            ];
            if (!accounts.isEmpty()) physicianId = accounts[0].Id;
        }

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
