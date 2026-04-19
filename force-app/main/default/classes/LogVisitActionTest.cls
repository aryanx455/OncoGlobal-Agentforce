@IsTest
private class LogVisitActionTest {

    @TestSetup
    static void makeData() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        Account physician = new Account(
            RecordTypeId = physicianRTId,
            Name         = 'Dr. Test Physician',
            Specialty__c = 'Oncology'
        );
        insert physician;
    }

    @IsTest
    static void testExecute_singleValidRequest_createsVisitReport() {
        Account physician = [SELECT Id FROM Account LIMIT 1];

        LogVisitAction.Request req = new LogVisitAction.Request();
        req.physicianId   = physician.Id;
        req.transcript    = 'Discussed new treatment protocol with Dr. Test.';
        req.visitOutcome  = 'Positive';
        req.visitType     = 'In-Person Clinic';
        req.engagementScore = 80;

        Test.startTest();
        List<LogVisitAction.Result> results = LogVisitAction.execute(
            new List<LogVisitAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assert(results[0].success, 'Should succeed');
        System.assertNotEquals(null, results[0].visitReportId, 'Should have a Visit Report ID');

        Visit_Report__c vr = [
            SELECT Physician__c, Visit_Outcome__c, Voice_Transcript__c, Engagement_Score__c
            FROM Visit_Report__c
            WHERE Id = :results[0].visitReportId
        ];
        System.assertEquals(physician.Id, vr.Physician__c);
        System.assertEquals('Positive', vr.Visit_Outcome__c);
        System.assertEquals(80, vr.Engagement_Score__c);
    }

    @IsTest
    static void testExecute_missingPhysicianId_returnsError() {
        LogVisitAction.Request req = new LogVisitAction.Request();
        req.transcript = 'Some transcript text';

        Test.startTest();
        List<LogVisitAction.Result> results = LogVisitAction.execute(
            new List<LogVisitAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(!results[0].success, 'Should fail without physician ID');
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @IsTest
    static void testExecute_defaultsApplied_whenOptionalFieldsBlank() {
        Account physician = [SELECT Id FROM Account LIMIT 1];

        LogVisitAction.Request req = new LogVisitAction.Request();
        req.physicianId = physician.Id;
        req.transcript  = 'Quick drop-in visit.';

        Test.startTest();
        List<LogVisitAction.Result> results = LogVisitAction.execute(
            new List<LogVisitAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success);
        Visit_Report__c vr = [
            SELECT Visit_Date__c, Visit_Outcome__c, Visit_Type__c
            FROM Visit_Report__c WHERE Id = :results[0].visitReportId
        ];
        System.assertEquals(Date.today(), vr.Visit_Date__c);
        System.assertEquals('Neutral', vr.Visit_Outcome__c);
        System.assertEquals('In-Person Clinic', vr.Visit_Type__c);
    }

    @IsTest
    static void testExecute_bulk_200Records_allSucceed() {
        Account physician = [SELECT Id FROM Account LIMIT 1];
        List<LogVisitAction.Request> requests = new List<LogVisitAction.Request>();
        for (Integer i = 0; i < 200; i++) {
            LogVisitAction.Request req = new LogVisitAction.Request();
            req.physicianId  = physician.Id;
            req.transcript   = 'Bulk test visit ' + i;
            req.visitOutcome = 'Neutral';
            requests.add(req);
        }

        Test.startTest();
        List<LogVisitAction.Result> results = LogVisitAction.execute(requests);
        Test.stopTest();

        Integer successCount = 0;
        for (LogVisitAction.Result res : results) {
            if (res.success) {
                successCount++;
            }
        }
        System.assertEquals(200, successCount, 'All 200 bulk inserts should succeed');
    }
}
