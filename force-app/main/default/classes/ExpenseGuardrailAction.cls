/**
 * Agentforce guardrail for expense duplicate detection and policy explanation.
 * Uses existing expense objects and configurable VisitPolicy__mdt limit.
 */
public with sharing class ExpenseGuardrailAction {

    public class Request {
        @InvocableVariable(label='Invoice Number')
        public String invoiceNumber;

        @InvocableVariable(label='Vendor Name')
        public String vendorName;

        @InvocableVariable(label='Amount')
        public Decimal amount;

        @InvocableVariable(label='Category')
        public String category;

        @InvocableVariable(label='Expense Date YYYY-MM-DD')
        public String expenseDate;

        @InvocableVariable(label='Doctor Name')
        public String doctorName;
    }

    public class Result {
        @InvocableVariable(label='Duplicate Found')
        public Boolean duplicateFound;

        @InvocableVariable(label='Duplicate Record ID')
        public String duplicateRecordId;

        @InvocableVariable(label='Duplicate Object')
        public String duplicateObject;

        @InvocableVariable(label='Policy Flagged')
        public Boolean policyFlagged;

        @InvocableVariable(label='Policy Limit')
        public Decimal policyLimit;

        @InvocableVariable(label='Policy Explanation')
        public String policyExplanation;

        @InvocableVariable(label='Risk Summary')
        public String riskSummary;

        @InvocableVariable(label='Recommended Action')
        public String recommendedAction;
    }

    @InvocableMethod(
        label='Review Expense Risk'
        description='Checks expense policy, explains policy flags, and detects duplicate uploaded or typed expenses before creation.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(review(req));
        }
        return results;
    }

    public static Id findDuplicateExpenseId(String invoiceNumber, String vendorName, Decimal amount, Date invoiceDate) {
        if (String.isNotBlank(invoiceNumber)) {
            List<Expense__c> byInvoice = [
                SELECT Id
                FROM Expense__c
                WHERE Invoice_Number__c = :invoiceNumber
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!byInvoice.isEmpty()) {
                return byInvoice[0].Id;
            }
        }

        if (String.isNotBlank(vendorName) && amount != null && invoiceDate != null) {
            List<Expense__c> byVendorAmountDate = [
                SELECT Id
                FROM Expense__c
                WHERE Vendor__c = :vendorName
                AND Amount__c = :amount
                AND Invoice_Date__c = :invoiceDate
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!byVendorAmountDate.isEmpty()) {
                return byVendorAmountDate[0].Id;
            }
        }

        if (String.isNotBlank(vendorName) && amount != null) {
            List<Expense__c> byVendorAmount = [
                SELECT Id
                FROM Expense__c
                WHERE Vendor__c = :vendorName
                AND Amount__c = :amount
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!byVendorAmount.isEmpty()) {
                return byVendorAmount[0].Id;
            }
        }

        return null;
    }

    private static Result review(Request req) {
        Result res = new Result();
        res.policyLimit = getPolicyLimit();
        res.policyFlagged = req != null && req.amount != null && req.amount > res.policyLimit;

        Date expenseDate = parseDate(req == null ? null : req.expenseDate);
        Id duplicateExpenseId = req == null
            ? null
            : findDuplicateExpenseId(req.invoiceNumber, req.vendorName, req.amount, expenseDate);

        if (duplicateExpenseId != null) {
            res.duplicateFound = true;
            res.duplicateRecordId = String.valueOf(duplicateExpenseId);
            res.duplicateObject = 'Expense__c';
        } else {
            Id duplicateVisitExpenseId = findDuplicateVisitExpense(req);
            res.duplicateFound = duplicateVisitExpenseId != null;
            res.duplicateRecordId = duplicateVisitExpenseId == null ? null : String.valueOf(duplicateVisitExpenseId);
            res.duplicateObject = duplicateVisitExpenseId == null ? null : 'Visit_Expense__c';
        }

        res.policyExplanation = buildPolicyExplanation(req, res.policyLimit, res.policyFlagged);
        res.riskSummary = buildRiskSummary(req, res);
        res.recommendedAction = buildRecommendedAction(res);
        return res;
    }

    private static Id findDuplicateVisitExpense(Request req) {
        if (req == null) {
            return null;
        }

        if (String.isNotBlank(req.invoiceNumber)) {
            List<Visit_Expense__c> byInvoice = [
                SELECT Id
                FROM Visit_Expense__c
                WHERE GST_Invoice_Number__c = :req.invoiceNumber
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!byInvoice.isEmpty()) {
                return byInvoice[0].Id;
            }
        }

        if (req.amount != null) {
            List<Visit_Expense__c> byAmount = [
                SELECT Id
                FROM Visit_Expense__c
                WHERE Amount__c = :req.amount
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!byAmount.isEmpty()) {
                return byAmount[0].Id;
            }
        }

        return null;
    }

    private static Decimal getPolicyLimit() {
        VisitPolicy__mdt policy = VisitPolicy__mdt.getInstance('Default_Policy');
        return policy == null || policy.Per_Visit_Limit__c == null ? 150 : policy.Per_Visit_Limit__c;
    }

    private static Date parseDate(String rawDate) {
        if (String.isBlank(rawDate)) {
            return null;
        }
        try {
            return Date.valueOf(rawDate);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String buildPolicyExplanation(Request req, Decimal limitAmount, Boolean flagged) {
        if (req == null || req.amount == null) {
            return 'Amount not provided, so policy risk cannot be evaluated.';
        }
        if (!flagged) {
            return 'Expense is within the Rs.' + String.valueOf(limitAmount) + ' policy limit.';
        }
        Decimal overage = req.amount - limitAmount;
        String categoryText = String.isBlank(req.category) ? 'Expense' : req.category + ' expense';
        return categoryText + ' exceeds the Rs.' + String.valueOf(limitAmount) +
            ' policy limit by Rs.' + String.valueOf(overage) + '.';
    }

    private static String buildRiskSummary(Request req, Result res) {
        List<String> parts = new List<String>();
        if (res.duplicateFound == true) {
            parts.add('Potential duplicate found in ' + res.duplicateObject + ': ' + res.duplicateRecordId);
        }
        if (res.policyFlagged == true) {
            parts.add(res.policyExplanation);
        }
        if (req != null && String.isBlank(req.doctorName)) {
            parts.add('Doctor was not provided; link this expense to a doctor or mark it for review.');
        }
        return parts.isEmpty() ? 'No duplicate or policy issue detected.' : String.join(parts, ' ');
    }

    private static String buildRecommendedAction(Result res) {
        if (res.duplicateFound == true) {
            return 'Do not create a new expense until the user confirms this is not a duplicate.';
        }
        if (res.policyFlagged == true) {
            return 'Create the expense with policy flag and explain the over-limit reason to the rep.';
        }
        return 'Safe to continue.';
    }
}
