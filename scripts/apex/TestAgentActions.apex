String physicianName = 'Dr. Priya Sharma';
String hospitalName = 'Apollo Cancer Centre';

LogVisitAction.Request visitReq = new LogVisitAction.Request();
visitReq.physicianName = physicianName;
visitReq.hospitalName = hospitalName;
visitReq.transcript = 'I visited Dr. Priya Sharma at Apollo Cancer Centre today. Discussed Keytruda. Positive visit.';
visitReq.visitOutcome = 'Positive';
visitReq.visitType = 'In-Person Clinic';

List<LogVisitAction.Result> visitResults =
    LogVisitAction.execute(new List<LogVisitAction.Request>{ visitReq });
System.debug('LOGVISIT=' + JSON.serializePretty(visitResults));

Id visitReportId = visitResults.isEmpty() ? null : visitResults[0].visitReportId;
Id physicianId = [SELECT Physician__c FROM Visit_Report__c WHERE Id = :visitReportId].Physician__c;

ExtractTopicsAction.Request extractReq = new ExtractTopicsAction.Request();
extractReq.visitReportId = visitReportId;
extractReq.discussionTopics = 'Keytruda; PD-L1; positive interest';
extractReq.nextBestAction = 'Send Keytruda literature';
extractReq.engagementScore = 91;
extractReq.aiSummary = 'Strong positive visit with clear follow-up.';
extractReq.needsReview = false;

List<ExtractTopicsAction.Result> extractResults =
    ExtractTopicsAction.execute(new List<ExtractTopicsAction.Request>{ extractReq });
System.debug('EXTRACTTOPICS=' + JSON.serializePretty(extractResults));

LogExpenseAction.Request expenseReq = new LogExpenseAction.Request();
expenseReq.amount = 450;
expenseReq.category = 'Meal';
expenseReq.physicianName = physicianName;
expenseReq.hospitalName = hospitalName;
expenseReq.visitDate = Date.today();
expenseReq.notes = 'Lunch at Apollo Cancer Centre';

List<LogExpenseAction.Result> expenseResults =
    LogExpenseAction.execute(new List<LogExpenseAction.Request>{ expenseReq });
System.debug('LOGEXPENSE=' + JSON.serializePretty(expenseResults));

CreateFollowUpTasksAction.Request taskReq = new CreateFollowUpTasksAction.Request();
taskReq.visitReportId = visitReportId;
taskReq.physicianName = physicianName;
taskReq.followUpActions = 'Send Keytruda literature, Schedule follow-up next week';
taskReq.priority = 'Normal';

List<CreateFollowUpTasksAction.Result> taskResults =
    CreateFollowUpTasksAction.execute(new List<CreateFollowUpTasksAction.Request>{ taskReq });
System.debug('CREATETASK=' + JSON.serializePretty(taskResults));

GetVisitInsightsAction.Request insightsReq = new GetVisitInsightsAction.Request();
insightsReq.physicianId = physicianId;

List<GetVisitInsightsAction.Result> insightResults =
    GetVisitInsightsAction.execute(new List<GetVisitInsightsAction.Request>{ insightsReq });
System.debug('GETVISITINSIGHTS=' + JSON.serializePretty(insightResults));

GetMedicalContextAction.Request contextReq = new GetMedicalContextAction.Request();
contextReq.category = 'DRUGS';

List<GetMedicalContextAction.Result> contextResults =
    GetMedicalContextAction.execute(new List<GetMedicalContextAction.Request>{ contextReq });
System.debug('GETMEDICALCONTEXT=' + JSON.serializePretty(contextResults));
