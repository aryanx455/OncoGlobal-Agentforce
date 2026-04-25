@IsTest
private class HealthCloudProviderBriefActionTest {

    @TestSetup
    static void makeData() {
        Account facility = new Account(
            Name = 'Onco Care Test Facility',
            Facility_Type__c = 'Hospital',
            Territory__c = 'Mumbai South'
        );
        insert facility;

        Account physicianAccount = new Account(
            Name = 'Dr. Health Cloud Test',
            ParentId = facility.Id,
            Specialty__c = 'Oncology',
            Territory__c = 'Mumbai South',
            Relationship_Score__c = 76,
            Preferred_Visit_Day__c = 'Tuesday',
            Preferred_Visit_Time__c = 'Morning (9am - 12pm)'
        );
        insert physicianAccount;

        Contact prescriber = new Contact(
            FirstName = 'Health',
            LastName = 'Cloud Test',
            AccountId = physicianAccount.Id,
            Specialty__c = 'Oncology',
            Relationship_Score__c = 81,
            Engagement_Score__c = 78,
            Total_Visits__c = 2,
            Last_Visit_Date__c = Date.today().addDays(-7),
            Influence_Level__c = 'Influencer',
            Prescribing_Potential__c = 'High'
        );
        insert prescriber;

        Visit_Report__c report = new Visit_Report__c(
            Physician__c = physicianAccount.Id,
            Rep__c = UserInfo.getUserId(),
            Visit_Date__c = Date.today().addDays(-7),
            Visit_Outcome__c = 'Positive',
            Engagement_Score__c = 78,
            Discussion_Topics__c = 'Keytruda response data, patient referral pathway',
            AI_Summary__c = 'Discussed Keytruda data and agreed to a follow-up on referral workflow.',
            Next_Best_Action__c = 'Send Keytruda summary and schedule a referral workflow review.'
        );
        if (Schema.SObjectType.Visit_Report__c.fields.getMap().containsKey('Prescriber__c')) {
            report.put('Prescriber__c', prescriber.Id);
        }
        if (Schema.SObjectType.Visit_Report__c.fields.getMap().containsKey('Hospital__c')) {
            report.put('Hospital__c', facility.Id);
        }
        insert report;

        insert new Task(
            Subject = 'Send Keytruda summary',
            WhatId = report.Id,
            OwnerId = UserInfo.getUserId(),
            ActivityDate = Date.today().addDays(2),
            Status = 'Not Started',
            Priority = 'Normal'
        );

        Account otherPhysician = new Account(
            Name = 'Dr. Same Facility Peer',
            ParentId = facility.Id,
            Specialty__c = 'Radiology',
            Territory__c = 'Mumbai South'
        );
        insert otherPhysician;

        Contact otherPrescriber = new Contact(
            FirstName = 'Same',
            LastName = 'Facility Peer',
            AccountId = otherPhysician.Id,
            Prescribing_Potential__c = 'Medium'
        );
        insert otherPrescriber;

        Visit_Report__c otherReport = new Visit_Report__c(
            Physician__c = otherPhysician.Id,
            Rep__c = UserInfo.getUserId(),
            Visit_Date__c = Date.today().addDays(-3),
            Visit_Outcome__c = 'Neutral',
            AI_Summary__c = 'Other doctor leakage sentinel.'
        );
        if (Schema.SObjectType.Visit_Report__c.fields.getMap().containsKey('Prescriber__c')) {
            otherReport.put('Prescriber__c', otherPrescriber.Id);
        }
        if (Schema.SObjectType.Visit_Report__c.fields.getMap().containsKey('Hospital__c')) {
            otherReport.put('Hospital__c', facility.Id);
        }
        insert otherReport;
    }

    @IsTest
    static void executeReturnsProviderBriefFromName() {
        HealthCloudProviderBriefAction.Request req = new HealthCloudProviderBriefAction.Request();
        req.providerName = 'Dr. Health Cloud Test';
        req.facilityName = 'Onco Care Test Facility';

        Test.startTest();
        List<HealthCloudProviderBriefAction.Result> results =
            HealthCloudProviderBriefAction.execute(new List<HealthCloudProviderBriefAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Expected provider brief by name to succeed.');
        System.assertEquals('Contact', results[0].providerRecordSource);
        System.assert(results[0].recentVisitSummary.contains('Keytruda'), 'Recent visits should be summarized.');
        System.assert(
            !results[0].recentVisitSummary.contains('Other doctor leakage sentinel'),
            'Provider brief should not include visits from other doctors at the same facility.'
        );
        System.assert(results[0].openTaskSummary.contains('Send Keytruda summary'), 'Open tasks should be summarized.');
        System.assert(String.isNotBlank(results[0].contextSummaryForAgent));
    }

    @IsTest
    static void executeReturnsProviderBriefFromContextIds() {
        Contact prescriber = [SELECT Id FROM Contact WHERE LastName = 'Cloud Test' LIMIT 1];

        HealthCloudProviderBriefAction.Request req = new HealthCloudProviderBriefAction.Request();
        req.contactId = prescriber.Id;

        Test.startTest();
        List<HealthCloudProviderBriefAction.Result> results =
            HealthCloudProviderBriefAction.execute(new List<HealthCloudProviderBriefAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected provider brief by context ID to succeed.');
        System.assertEquals('Contact', results[0].providerRecordSource);
        System.assert(results[0].relationshipSnapshot.contains('Relationship Score'));
    }

    @IsTest
    static void executeRequiresProviderContext() {
        HealthCloudProviderBriefAction.Request req = new HealthCloudProviderBriefAction.Request();

        Test.startTest();
        List<HealthCloudProviderBriefAction.Result> results =
            HealthCloudProviderBriefAction.execute(new List<HealthCloudProviderBriefAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(String.isNotBlank(results[0].errorMessage));
    }
}
