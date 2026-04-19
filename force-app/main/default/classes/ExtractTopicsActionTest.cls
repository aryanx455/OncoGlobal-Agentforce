@IsTest
private class ExtractTopicsActionTest {

    @TestSetup
    static void makeData() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        Account physician = new Account(RecordTypeId = physicianRTId, Name = 'Dr. Extract Test');
        insert physician;

        Visit_Report__c vr = new Visit_Report__c(
            Physician__c     = physician.Id,
            Rep__c           = UserInfo.getUserId(),
            Visit_Date__c    = Date.today(),
            Visit_Outcome__c = 'Neutral'
        );
        insert vr;
    }

    @IsTest
    static void testExecute_updatesAllFields() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];

        ExtractTopicsAction.Request req = new ExtractTopicsAction.Request();
        req.visitReportId    = vr.Id;
        req.discussionTopics = 'Keytruda efficacy, patient referral, trial enrollment';
        req.nextBestAction   = 'Send clinical trial brochure within 48 hours';
        req.engagementScore  = 75;
        req.aiSummary        = 'Productive visit. Dr. interested in trial enrollment.';
        req.needsReview      = false;

        Test.startTest();
        List<ExtractTopicsAction.Result> results = ExtractTopicsAction.execute(
            new List<ExtractTopicsAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success, 'Should succeed');
        Visit_Report__c updated = [
            SELECT Discussion_Topics__c, Next_Best_Action__c, Engagement_Score__c,
                   AI_Summary__c, Needs_Review__c
            FROM Visit_Report__c WHERE Id = :vr.Id
        ];
        System.assertEquals('Keytruda efficacy, patient referral, trial enrollment', updated.Discussion_Topics__c);
        System.assertEquals('Send clinical trial brochure within 48 hours', updated.Next_Best_Action__c);
        System.assertEquals(75, updated.Engagement_Score__c);
        System.assert(!updated.Needs_Review__c);
    }

    @IsTest
    static void testExecute_invalidId_returnsError() {
        ExtractTopicsAction.Request req = new ExtractTopicsAction.Request();
        req.visitReportId    = null;
        req.discussionTopics = 'Some topics';

        Test.startTest();
        List<ExtractTopicsAction.Result> results = ExtractTopicsAction.execute(
            new List<ExtractTopicsAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(!results[0].success);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @IsTest
    static void testExecute_bulk_100Updates() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        Account physician = [SELECT Id FROM Account LIMIT 1];

        List<Visit_Report__c> reports = new List<Visit_Report__c>();
        for (Integer i = 0; i < 100; i++) {
            reports.add(new Visit_Report__c(
                Physician__c = physician.Id, Rep__c = UserInfo.getUserId(),
                Visit_Date__c = Date.today(), Visit_Outcome__c = 'Neutral'
            ));
        }
        insert reports;

        List<ExtractTopicsAction.Request> requests = new List<ExtractTopicsAction.Request>();
        for (Visit_Report__c vr : reports) {
            ExtractTopicsAction.Request req = new ExtractTopicsAction.Request();
            req.visitReportId   = vr.Id;
            req.discussionTopics = 'Bulk topic ' + vr.Id;
            req.engagementScore  = 60;
            requests.add(req);
        }

        Test.startTest();
        List<ExtractTopicsAction.Result> results = ExtractTopicsAction.execute(requests);
        Test.stopTest();

        Integer successCount = 0;
        for (ExtractTopicsAction.Result res : results) {
            if (res.success) successCount++;
        }
        System.assertEquals(100, successCount);
    }
}
