@IsTest
private class LogExpenseActionTest {

    @TestSetup
    static void makeData() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        Account physician = new Account(RecordTypeId = physicianRTId, Name = 'Dr. Expense Test');
        insert physician;

        Visit_Report__c vr = new Visit_Report__c(
            Physician__c     = physician.Id,
            Rep__c           = UserInfo.getUserId(),
            Visit_Date__c    = Date.today(),
            Visit_Outcome__c = 'Positive'
        );
        insert vr;
    }

    @IsTest
    static void testExecute_validExpense_belowThreshold_notFlagged() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];

        LogExpenseAction.Request req = new LogExpenseAction.Request();
        req.visitReportId = vr.Id;
        req.amount        = 100;
        req.category      = 'Meal';
        req.notes         = 'Team lunch at hospital canteen';

        Test.startTest();
        List<LogExpenseAction.Result> results = LogExpenseAction.execute(
            new List<LogExpenseAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success, 'Should succeed');
        System.assertNotEquals(null, results[0].expenseId);
        System.assert(!results[0].policyFlagged, 'Amount 100 should not be flagged (threshold 150)');

        Expense__c exp = [SELECT Visit_Report__c FROM Expense__c WHERE Id = :results[0].expenseId];
        System.assertEquals(vr.Id, exp.Visit_Report__c, 'Expense should be linked to the visit report');
    }

    @IsTest
    static void testExecute_validExpense_aboveThreshold_isFlagged() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];

        LogExpenseAction.Request req = new LogExpenseAction.Request();
        req.visitReportId = vr.Id;
        req.amount        = 250;
        req.category      = 'Travel';
        req.notes         = 'Flight to Bangalore';

        Test.startTest();
        List<LogExpenseAction.Result> results = LogExpenseAction.execute(
            new List<LogExpenseAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success);
        System.assert(results[0].policyFlagged, 'Amount 250 should be flagged');
    }

    @IsTest
    static void testExecute_zeroAmount_returnsError() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];

        LogExpenseAction.Request req = new LogExpenseAction.Request();
        req.visitReportId = vr.Id;
        req.amount        = 0;
        req.category      = 'Meal';

        Test.startTest();
        List<LogExpenseAction.Result> results = LogExpenseAction.execute(
            new List<LogExpenseAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(!results[0].success, 'Zero amount should fail');
    }

    @IsTest
    static void testExecute_missingCategory_returnsError() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];

        LogExpenseAction.Request req = new LogExpenseAction.Request();
        req.visitReportId = vr.Id;
        req.amount        = 80;

        Test.startTest();
        List<LogExpenseAction.Result> results = LogExpenseAction.execute(
            new List<LogExpenseAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(!results[0].success, 'Missing category should fail');
    }

    @IsTest
    static void testExecute_bulk_multipleExpenses() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];
        List<LogExpenseAction.Request> requests = new List<LogExpenseAction.Request>();

        String[] categories = new String[]{ 'Meal', 'Travel', 'Accommodation', 'Samples', 'CME / Event' };
        for (Integer i = 0; i < 5; i++) {
            LogExpenseAction.Request req = new LogExpenseAction.Request();
            req.visitReportId = vr.Id;
            req.amount        = 50 + (i * 50);
            req.category      = categories[i];
            requests.add(req);
        }

        Test.startTest();
        List<LogExpenseAction.Result> results = LogExpenseAction.execute(requests);
        Test.stopTest();

        Integer successCount = 0;
        for (LogExpenseAction.Result res : results) {
            if (res.success) successCount++;
        }
        System.assertEquals(5, successCount, 'All 5 expenses should be created');

        Visit_Report__c updatedVr = [SELECT Total_Expense_Amount__c FROM Visit_Report__c WHERE Id = :vr.Id];
        System.assertEquals(750, updatedVr.Total_Expense_Amount__c, 'Rollup should total 50+100+150+200+250=750');
    }
}
