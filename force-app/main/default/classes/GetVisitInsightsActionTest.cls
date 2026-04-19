@IsTest
private class GetVisitInsightsActionTest {

    @TestSetup
    static void makeData() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        Account physician = new Account(
            RecordTypeId            = physicianRTId,
            Name                    = 'Dr. Insights Test',
            Specialty__c            = 'Oncology',
            Territory__c            = 'Mumbai South',
            Key_Account__c          = true,
            Preferred_Visit_Day__c  = 'Tuesday',
            Preferred_Visit_Time__c = 'Morning (9am–12pm)'
        );
        insert physician;

        List<Visit_Report__c> visits = new List<Visit_Report__c>{
            new Visit_Report__c(
                Physician__c        = physician.Id,
                Rep__c              = UserInfo.getUserId(),
                Visit_Date__c       = Date.today().addDays(-5),
                Visit_Outcome__c    = 'Positive',
                Engagement_Score__c = 85,
                Discussion_Topics__c = 'Trial enrollment, Keytruda data'
            ),
            new Visit_Report__c(
                Physician__c        = physician.Id,
                Rep__c              = UserInfo.getUserId(),
                Visit_Date__c       = Date.today().addDays(-15),
                Visit_Outcome__c    = 'Neutral',
                Engagement_Score__c = 55,
                Discussion_Topics__c = 'Formulary listing, samples'
            ),
            new Visit_Report__c(
                Physician__c        = physician.Id,
                Rep__c              = UserInfo.getUserId(),
                Visit_Date__c       = Date.today().addDays(-30),
                Visit_Outcome__c    = 'Negative',
                Engagement_Score__c = 30,
                Discussion_Topics__c = 'TAT concerns, diagnostics'
            )
        };
        insert visits;
    }

    @IsTest
    static void testExecute_returnsPhysicianContext() {
        Account physician = [SELECT Id FROM Account LIMIT 1];

        GetVisitInsightsAction.Request req = new GetVisitInsightsAction.Request();
        req.physicianId = physician.Id;

        Test.startTest();
        List<GetVisitInsightsAction.Result> results = GetVisitInsightsAction.execute(
            new List<GetVisitInsightsAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success, 'Should succeed');
        System.assertEquals('Dr. Insights Test', results[0].physicianName);
        System.assertEquals('Oncology', results[0].specialty);
        System.assertEquals('Mumbai South', results[0].territory);
        System.assert(results[0].isKeyAccount);
        System.assertNotEquals(null, results[0].contextSummaryForAI);
        System.assertNotEquals(null, results[0].recentTopics);
    }

    @IsTest
    static void testExecute_recentTopicsPopulated() {
        Account physician = [SELECT Id FROM Account LIMIT 1];

        GetVisitInsightsAction.Request req = new GetVisitInsightsAction.Request();
        req.physicianId = physician.Id;

        Test.startTest();
        List<GetVisitInsightsAction.Result> results = GetVisitInsightsAction.execute(
            new List<GetVisitInsightsAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(String.isNotBlank(results[0].recentTopics));
        System.assert(results[0].recentTopics.contains('Trial enrollment'));
        System.assertNotEquals(null, results[0].lastVisitOutcome);
    }

    @IsTest
    static void testExecute_invalidPhysicianId_returnsError() {
        GetVisitInsightsAction.Request req = new GetVisitInsightsAction.Request();
        req.physicianId = null;

        Test.startTest();
        List<GetVisitInsightsAction.Result> results = GetVisitInsightsAction.execute(
            new List<GetVisitInsightsAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(!results[0].success);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @IsTest
    static void testExecute_bulk_multiplePhysicians() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        List<Account> physicians = new List<Account>();
        for (Integer i = 0; i < 10; i++) {
            physicians.add(new Account(
                RecordTypeId = physicianRTId,
                Name         = 'Dr. Bulk ' + i,
                Specialty__c = 'Oncology'
            ));
        }
        insert physicians;

        List<GetVisitInsightsAction.Request> requests = new List<GetVisitInsightsAction.Request>();
        for (Account p : physicians) {
            GetVisitInsightsAction.Request req = new GetVisitInsightsAction.Request();
            req.physicianId = p.Id;
            requests.add(req);
        }

        Test.startTest();
        List<GetVisitInsightsAction.Result> results = GetVisitInsightsAction.execute(requests);
        Test.stopTest();

        System.assertEquals(10, results.size());
        for (GetVisitInsightsAction.Result res : results) {
            System.assert(res.success, 'All bulk requests should succeed');
        }
    }
}
