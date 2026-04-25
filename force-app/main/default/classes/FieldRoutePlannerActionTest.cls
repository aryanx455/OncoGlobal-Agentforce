@IsTest
private class FieldRoutePlannerActionTest {

    @IsTest
    static void executeBuildsRoutePlan() {
        Account facility = new Account(
            Name = 'Route Test Hospital',
            Territory__c = 'Mumbai South'
        );
        insert facility;

        Contact doctor = new Contact(
            FirstName = 'Route',
            LastName = 'Doctor',
            AccountId = facility.Id,
            Specialty__c = 'Oncology',
            Relationship_Score__c = 42,
            Prescribing_Potential__c = 'High',
            Do_Not_Visit__c = false
        );
        insert doctor;

        insert new Task(
            Subject = 'Follow up route doctor',
            WhoId = doctor.Id,
            OwnerId = UserInfo.getUserId(),
            ActivityDate = Date.today().addDays(1),
            Status = 'Not Started',
            Priority = 'Normal'
        );

        FieldRoutePlannerAction.Request req = new FieldRoutePlannerAction.Request();
        req.territory = 'Mumbai South';
        req.plannedDate = String.valueOf(Date.today().addDays(1));
        req.maxStops = 3;

        Test.startTest();
        List<FieldRoutePlannerAction.Result> results =
            FieldRoutePlannerAction.execute(new List<FieldRoutePlannerAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected route planning to succeed.');
        System.assert(results[0].recommendedStops.contains('Route Doctor'));
        System.assert(results[0].standardObjectUsage.contains('Contact'));
    }
}
