@IsTest
private class CreateFollowUpTasksActionTest {

    @TestSetup
    static void makeData() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        Account physician = new Account(RecordTypeId = physicianRTId, Name = 'Dr. Task Test');
        insert physician;

        Visit_Report__c vr = new Visit_Report__c(
            Physician__c     = physician.Id,
            Rep__c           = UserInfo.getUserId(),
            Visit_Date__c    = Date.today(),
            Visit_Outcome__c = 'Follow-Up Required'
        );
        insert vr;
    }

    @IsTest
    static void testExecute_newlineSeparated_createsTasks() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];
        Account physician   = [SELECT Id FROM Account LIMIT 1];

        CreateFollowUpTasksAction.Request req = new CreateFollowUpTasksAction.Request();
        req.visitReportId  = vr.Id;
        req.physicianId    = physician.Id;
        req.followUpActions = 'Send clinical trial brochure\nSchedule CME event\nFollow up on formulary listing';
        req.priority        = 'High';

        Test.startTest();
        List<CreateFollowUpTasksAction.Result> results = CreateFollowUpTasksAction.execute(
            new List<CreateFollowUpTasksAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success, 'Should succeed');
        System.assertEquals(3, results[0].tasksCreated, 'Should create 3 tasks');

        List<Task> tasks = [SELECT Subject, Priority, WhatId FROM Task WHERE WhatId = :vr.Id];
        System.assertEquals(3, tasks.size());
        System.assertEquals('High', tasks[0].Priority);
    }

    @IsTest
    static void testExecute_commaSeparated_createsTasks() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];
        Account physician   = [SELECT Id FROM Account LIMIT 1];

        CreateFollowUpTasksAction.Request req = new CreateFollowUpTasksAction.Request();
        req.visitReportId   = vr.Id;
        req.physicianId     = physician.Id;
        req.followUpActions = 'Email samples; Call back next week; Submit expense report';

        Test.startTest();
        List<CreateFollowUpTasksAction.Result> results = CreateFollowUpTasksAction.execute(
            new List<CreateFollowUpTasksAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success);
        System.assertEquals(3, results[0].tasksCreated);
    }

    @IsTest
    static void testExecute_missingReportId_returnsError() {
        CreateFollowUpTasksAction.Request req = new CreateFollowUpTasksAction.Request();
        req.physicianId     = [SELECT Id FROM Account LIMIT 1].Id;
        req.followUpActions = 'Do something';

        Test.startTest();
        List<CreateFollowUpTasksAction.Result> results = CreateFollowUpTasksAction.execute(
            new List<CreateFollowUpTasksAction.Request>{ req }
        );
        Test.stopTest();

        System.assert(!results[0].success);
    }

    @IsTest
    static void testParseActions_numberedList_stripsNumbers() {
        String input = '1. Send brochure\n2. Call physician\n3. Submit report';
        List<String> actions = CreateFollowUpTasksAction.parseActions(input);
        System.assertEquals(3, actions.size());
        System.assert(!actions[0].startsWith('1'), 'Should strip numbering');
    }

    @IsTest
    static void testExecute_defaultDueDate_isThreeDaysFromToday() {
        Visit_Report__c vr = [SELECT Id FROM Visit_Report__c LIMIT 1];
        Account physician   = [SELECT Id FROM Account LIMIT 1];

        CreateFollowUpTasksAction.Request req = new CreateFollowUpTasksAction.Request();
        req.visitReportId   = vr.Id;
        req.physicianId     = physician.Id;
        req.followUpActions = 'Single follow-up task';

        Test.startTest();
        CreateFollowUpTasksAction.execute(new List<CreateFollowUpTasksAction.Request>{ req });
        Test.stopTest();

        Task t = [SELECT ActivityDate FROM Task WHERE WhatId = :vr.Id LIMIT 1];
        System.assertEquals(Date.today().addDays(3), t.ActivityDate);
    }
}
