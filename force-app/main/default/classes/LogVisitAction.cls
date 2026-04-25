/**
 * Creates a Visit_Report__c from a rep's post-visit note.
 * The agent should pass names, not Salesforce IDs; this class resolves the
 * doctor safely and asks for clarification instead of creating weak data.
 */
public without sharing class LogVisitAction {
    public class Request {
        @InvocableVariable(label='Voice Transcript'
            description='Full rep statement about the completed visit. Required.')
        public String transcript;

        @InvocableVariable(label='Physician Name'
            description='Doctor/provider name as spoken by the rep, e.g. Doctor Demo 004.')
        public String physicianName;

        @InvocableVariable(label='Hospital or Facility Name'
            description='Facility only when the rep mentioned it or when duplicate doctors need disambiguation.')
        public String hospitalName;

        @InvocableVariable(label='Physician Account ID')
        public Id physicianId;

        @InvocableVariable(label='Visit Outcome')
        public String visitOutcome;

        @InvocableVariable(label='Visit Type')
        public String visitType;

        @InvocableVariable(label='Visit Date (defaults to today)')
        public Date visitDate;

        @InvocableVariable(label='AI Generated Summary')
        public String aiSummary;

        @InvocableVariable(label='Engagement Score (0-100)')
        public Decimal engagementScore;
    }

    public class Result {
        @InvocableVariable(label='Visit Report ID')
        public Id visitReportId;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Needs Clarification')
        public Boolean needsClarification;

        @InvocableVariable(label='Clarification Message')
        public String clarificationMessage;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Visit Report Name')
        public String visitReportName;

        @InvocableVariable(label='Physician Name (resolved)')
        public String resolvedPhysicianName;

        @InvocableVariable(label='Physician Account ID (resolved)')
        public Id physicianAccountId;

        @InvocableVariable(label='Prescriber Contact ID')
        public Id prescriberContactId;

        @InvocableVariable(label='Hospital Account ID')
        public Id hospitalAccountId;

        @InvocableVariable(label='Facility Name (resolved)')
        public String resolvedFacilityName;
    }

    @InvocableMethod(
        label='Log Post-Visit Report'
        description='Creates a Visit_Report__c from a post-visit note. Resolves doctor/facility by name and asks for clarification on duplicates.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<Visit_Report__c> reportsToInsert = new List<Visit_Report__c>();
        List<Integer> resultIndexes = new List<Integer>();
        Map<Id, String> accountNamesById = loadAccountNames(requests);
        Map<String, Schema.SObjectField> visitFields = Schema.SObjectType.Visit_Report__c.fields.getMap();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = baseResult();

            if (req == null || String.isBlank(req.transcript)) {
                res.errorMessage = 'Transcript is required.';
                results.add(res);
                continue;
            }

            Id resolvedPhysicianId = req.physicianId;
            Id prescriberContactId;
            Id hospitalAccountId;
            String resolvedPhysicianName = req.physicianId == null ? null : accountNamesById.get(req.physicianId);
            String resolvedFacilityName;

            if (resolvedPhysicianId == null && String.isNotBlank(req.physicianName)) {
                ProviderResolutionService.Resolution resolution = ProviderResolutionService.resolveDoctor(
                    req.physicianName,
                    req.hospitalName,
                    true,
                    true
                );
                if (resolution.success != true) {
                    applyClarification(res, resolution);
                    results.add(res);
                    continue;
                }
                resolvedPhysicianId = resolution.physicianAccountId;
                prescriberContactId = resolution.doctorContactId;
                hospitalAccountId = resolution.facilityAccountId;
                resolvedPhysicianName = String.isNotBlank(resolution.physicianName)
                    ? resolution.physicianName
                    : resolution.contactName;
                resolvedFacilityName = resolution.facilityName;
            }

            res.resolvedPhysicianName = String.isNotBlank(resolvedPhysicianName)
                ? resolvedPhysicianName
                : req.physicianName;
            res.physicianAccountId = resolvedPhysicianId;
            res.prescriberContactId = prescriberContactId;
            res.hospitalAccountId = hospitalAccountId;
            res.resolvedFacilityName = resolvedFacilityName;

            Visit_Report__c report = new Visit_Report__c(
                Physician__c = resolvedPhysicianId,
                Rep__c = UserInfo.getUserId(),
                Voice_Transcript__c = req.transcript,
                Visit_Date__c = req.visitDate != null ? req.visitDate : Date.today(),
                Visit_Outcome__c = String.isNotBlank(req.visitOutcome) ? req.visitOutcome : 'Neutral',
                Visit_Type__c = String.isNotBlank(req.visitType) ? req.visitType : 'In-Person Clinic',
                AI_Summary__c = req.aiSummary,
                Engagement_Score__c = req.engagementScore
            );
            if (visitFields.containsKey('Prescriber__c') && prescriberContactId != null) {
                report.put('Prescriber__c', prescriberContactId);
            }
            if (visitFields.containsKey('Hospital__c') && hospitalAccountId != null) {
                report.put('Hospital__c', hospitalAccountId);
            }

            reportsToInsert.add(report);
            resultIndexes.add(results.size());
            results.add(res);
        }

        if (!reportsToInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(reportsToInsert, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Result res = results[resultIndexes[i]];
                if (saveResults[i].isSuccess()) {
                    res.success = true;
                    res.visitReportId = saveResults[i].getId();
                    res.visitReportName = reportsToInsert[i].Name;
                } else {
                    res.errorMessage = saveResults[i].getErrors()[0].getMessage();
                }
            }
        }

        return results;
    }

    private static Result baseResult() {
        Result res = new Result();
        res.success = false;
        res.needsClarification = false;
        return res;
    }

    private static void applyClarification(Result res, ProviderResolutionService.Resolution resolution) {
        res.success = false;
        res.needsClarification = true;
        res.clarificationMessage = resolution.clarificationMessage;
        res.errorMessage = resolution.errorMessage;
    }

    private static Map<Id, String> loadAccountNames(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.physicianId != null) {
                ids.add(req.physicianId);
            }
        }

        Map<Id, String> names = new Map<Id, String>();
        if (!ids.isEmpty()) {
            for (Account accountRecord : [SELECT Id, Name FROM Account WHERE Id IN :ids]) {
                names.put(accountRecord.Id, accountRecord.Name);
            }
        }
        return names;
    }
}
