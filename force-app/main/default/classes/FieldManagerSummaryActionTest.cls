@IsTest
private class FieldManagerSummaryActionTest {

    @IsTest
    static void executeBuildsManagerSummary() {
        Account facility = new Account(Name = 'Summary Hospital', Territory__c = 'Mumbai South');
        insert facility;

        Contact doctor = new Contact(
            FirstName = 'Summary',
            LastName = 'Doctor',
            AccountId = facility.Id,
            Prescribing_Potential__c = 'High',
            Do_Not_Visit__c = false,
            Relationship_Score__c = 88
        );
        insert doctor;

        Visit_Report__c visit = new Visit_Report__c(
            Prescriber__c = doctor.Id,
            Hospital__c = facility.Id,
            Rep__c = UserInfo.getUserId(),
            Visit_Date__c = Date.today(),
            Visit_Outcome__c = 'Positive',
            Engagement_Score__c = 85
        );
        insert visit;

        insert new Visit_Expense__c(
            Visit_Report__c = visit.Id,
            Amount__c = 450,
            Category__c = 'Meal'
        );

        insert new Expense__c(
            Vendor__c = 'Summary Cafe',
            Amount__c = 300,
            Invoice_Number__c = 'SUM-' + String.valueOf(Crypto.getRandomInteger()),
            Invoice_Date__c = Date.today()
        );

        insert new Task(
            Subject = 'Send summary brochure',
            WhoId = doctor.Id,
            OwnerId = UserInfo.getUserId(),
            ActivityDate = Date.today().addDays(1),
            Status = 'Not Started',
            Priority = 'Normal'
        );

        FieldManagerSummaryAction.Request req = new FieldManagerSummaryAction.Request();
        req.startDate = String.valueOf(Date.today().addDays(-1));
        req.endDate = String.valueOf(Date.today());

        Test.startTest();
        List<FieldManagerSummaryAction.Result> results =
            FieldManagerSummaryAction.execute(new List<FieldManagerSummaryAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected manager summary to succeed.');
        System.assert(results[0].visitCount >= 1);
        System.assert(results[0].managerSummary.contains('Visits logged'));
        System.assert(results[0].highPotentialDoctors.contains('Summary Doctor'));
    }
}
