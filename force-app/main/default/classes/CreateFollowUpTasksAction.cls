/**
 * CreateFollowUpTasksAction
 * @InvocableMethod — called by Agentforce to auto-create follow-up Tasks
 * from AI-extracted action items after a physician visit.
 *
 * Accepts physician name and/or visit report ID — resolves via SOQL if only
 * name is provided so the agent never needs raw Salesforce IDs.
 */
public without sharing class CreateFollowUpTasksAction {

    private static final Integer DEFAULT_DUE_DAYS = 3;

    // ─── INPUT / OUTPUT ────────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(required=true label='Follow-Up Actions'
            description='Comma-separated or newline-separated list of follow-up actions to create as Tasks (e.g. "Send Tagrisso literature to Dr. Gupta, Arrange CME next month").')
        public String followUpActions;

        @InvocableVariable(label='Physician Name'
            description='Name of the physician as spoken by the rep (e.g. "Dr. Gupta"). Used to link tasks to the correct account when Visit Report ID is not available.')
        public String physicianName;

        @InvocableVariable(label='Hospital or Facility Name'
            description='Hospital/clinic name only when needed to disambiguate duplicate doctors.')
        public String hospitalName;

        @InvocableVariable(label='Visit Report ID'
            description='Salesforce ID of the Visit Report to link tasks to. Optional — if not provided, the agent will search for today\'s visit report for the named physician.')
        public Id visitReportId;

        @InvocableVariable(label='Physician Account ID'
            description='Salesforce Account ID of the physician. Optional — Physician Name is used for lookup when this is not available.')
        public Id physicianId;

        @InvocableVariable(label='Due Date (defaults to 3 days from today)')
        public Date dueDate;

        @InvocableVariable(label='Priority (High / Normal / Low)')
        public String priority;
    }

    public class Result {
        @InvocableVariable(label='Tasks Created Count')
        public Integer tasksCreated;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Needs Clarification')
        public Boolean needsClarification;

        @InvocableVariable(label='Clarification Message')
        public String clarificationMessage;

        @InvocableVariable(label='Resolved Physician Name')
        public String resolvedPhysicianName;

        @InvocableVariable(label='Resolved Facility Name')
        public String resolvedFacilityName;

        @InvocableVariable(label='Task IDs (comma-separated)')
        public String taskIds;
    }

    // ─── INVOCABLE ENTRY POINT ─────────────────────────────────────────────────

    @InvocableMethod(
        label='Create Follow-Up Tasks from Visit'
        description='Parses follow-up actions and creates Task records. Accepts physician name (e.g. "Dr. Gupta") — no Salesforce IDs needed. Provide the follow-up actions as a comma-separated list.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Task> allTasks = new List<Task>();
        List<Result> results = new List<Result>();
        List<Integer> resultStartIndex = new List<Integer>();
        List<Integer> resultTaskCount = new List<Integer>();

        for (Request req : requests) {
            Result res = new Result();
            res.success = false;
            res.needsClarification = false;

            if (String.isBlank(req.followUpActions)) {
                res.errorMessage = 'Follow-Up Actions are required.';
                results.add(res);
                resultStartIndex.add(-1);
                resultTaskCount.add(0);
                continue;
            }

            List<String> actionItems = parseActions(req.followUpActions);
            if (actionItems.isEmpty()) {
                res.errorMessage = 'No actionable items found in the provided text.';
                results.add(res);
                resultStartIndex.add(-1);
                resultTaskCount.add(0);
                continue;
            }

            // ── Resolve doctor context before creating tasks ─────────────────
            Id whatId = req.visitReportId;
            Id whoId;
            Id physicianId = req.physicianId;
            if (String.isNotBlank(req.physicianName)) {
                ProviderResolutionService.Resolution resolution = ProviderResolutionService.resolveDoctor(
                    req.physicianName,
                    req.hospitalName,
                    false,
                    true
                );
                if (resolution.success != true) {
                    res.needsClarification = true;
                    res.clarificationMessage = resolution.clarificationMessage;
                    res.errorMessage = resolution.errorMessage;
                    results.add(res);
                    resultStartIndex.add(-1);
                    resultTaskCount.add(0);
                    continue;
                }
                physicianId = resolution.physicianAccountId != null ? resolution.physicianAccountId : physicianId;
                whoId = resolution.doctorContactId;
                res.resolvedPhysicianName = String.isNotBlank(resolution.physicianName)
                    ? resolution.physicianName
                    : resolution.contactName;
                res.resolvedFacilityName = resolution.facilityName;
            }

            if (whatId == null && physicianId != null) {
                whatId = findTodaysVisitReport(physicianId);
            }
            if (whatId == null && physicianId != null) {
                whatId = physicianId;
            }

            Date taskDueDate = req.dueDate != null ? req.dueDate : Date.today().addDays(DEFAULT_DUE_DAYS);
            String taskPriority = String.isNotBlank(req.priority) ? req.priority : 'Normal';

            resultStartIndex.add(allTasks.size());
            resultTaskCount.add(actionItems.size());

            for (String action : actionItems) {
                allTasks.add(new Task(
                    Subject         = action.abbreviate(255),
                    WhoId           = whoId,
                    WhatId          = whatId,
                    OwnerId         = UserInfo.getUserId(),
                    ActivityDate    = taskDueDate,
                    Priority        = taskPriority,
                    Status          = 'Not Started',
                    Description     = 'Auto-created by Agentforce PostVisitLogAgent from visit transcript.'
                                      + (String.isNotBlank(req.physicianName) ? ' Physician: ' + req.physicianName : '')
                ));
            }

            results.add(res);
        }

        if (!allTasks.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(allTasks, false);

            for (Integer i = 0; i < results.size(); i++) {
                Integer startIdx = resultStartIndex[i];
                Integer count = resultTaskCount[i];
                if (startIdx < 0) {
                    continue;
                }

                Result res = results[i];
                List<String> createdIds = new List<String>();
                Boolean allSuccess = true;
                String firstError = '';

                for (Integer j = startIdx; j < startIdx + count; j++) {
                    if (saveResults[j].isSuccess()) {
                        createdIds.add(saveResults[j].getId());
                    } else {
                        allSuccess = false;
                        if (String.isBlank(firstError)) {
                            firstError = saveResults[j].getErrors()[0].getMessage();
                        }
                    }
                }

                res.tasksCreated = createdIds.size();
                res.taskIds = String.join(createdIds, ',');
                res.success = allSuccess;
                if (!allSuccess) {
                    res.errorMessage = firstError;
                }
            }
        }

        return results;
    }

    // ─── HELPERS ──────────────────────────────────────────────────────────────

    @TestVisible
    private static List<String> parseActions(String rawText) {
        List<String> actions = new List<String>();
        if (String.isBlank(rawText)) {
            return actions;
        }
        String cleaned = rawText.replaceAll('\\r\\n|\\r', '\n');
        cleaned = cleaned.replaceAll('\\d+\\.\\s+', '\n');
        List<String> parts = cleaned.split('[;,\n]');
        for (String part : parts) {
            String trimmed = part.trim();
            if (trimmed.length() > 3) {
                actions.add(trimmed);
            }
        }
        return actions;
    }

    private static Id findTodaysVisitReport(Id physicianId) {
        Id currentUserId = UserInfo.getUserId();
        List<Visit_Report__c> reports = [
            SELECT Id FROM Visit_Report__c
            WHERE Visit_Date__c = :Date.today()
            AND Physician__c = :physicianId
            AND (OwnerId = :currentUserId OR Rep__c = :currentUserId)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return reports.isEmpty() ? null : reports[0].Id;
    }
}
