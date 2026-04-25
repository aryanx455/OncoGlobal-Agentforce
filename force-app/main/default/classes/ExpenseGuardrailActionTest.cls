@IsTest
private class ExpenseGuardrailActionTest {

    @IsTest
    static void executeFlagsDuplicateAndPolicy() {
        Expense__c existing = new Expense__c(
            Vendor__c = 'Policy Cafe',
            Amount__c = 500,
            Invoice_Number__c = 'POL-001',
            Invoice_Date__c = Date.today()
        );
        insert existing;

        ExpenseGuardrailAction.Request req = new ExpenseGuardrailAction.Request();
        req.invoiceNumber = 'POL-001';
        req.vendorName = 'Policy Cafe';
        req.amount = 500;
        req.category = 'Meal';
        req.expenseDate = String.valueOf(Date.today());
        req.doctorName = 'Dr. Policy';

        Test.startTest();
        List<ExpenseGuardrailAction.Result> results =
            ExpenseGuardrailAction.execute(new List<ExpenseGuardrailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].duplicateFound);
        System.assertEquals(true, results[0].policyFlagged);
        System.assert(results[0].policyExplanation.contains('exceeds'));
    }

    @IsTest
    static void executeAllowsSafeExpense() {
        ExpenseGuardrailAction.Request req = new ExpenseGuardrailAction.Request();
        req.vendorName = 'Safe Vendor';
        req.amount = 100;
        req.category = 'Travel';
        req.doctorName = 'Dr. Safe';

        List<ExpenseGuardrailAction.Result> results =
            ExpenseGuardrailAction.execute(new List<ExpenseGuardrailAction.Request>{ req });

        System.assertEquals(false, results[0].duplicateFound);
        System.assertEquals(false, results[0].policyFlagged);
        System.assertEquals('Safe to continue.', results[0].recommendedAction);
    }
}
