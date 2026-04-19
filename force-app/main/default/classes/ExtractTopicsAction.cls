/**
 * ExtractTopicsAction
 * @InvocableMethod — called by Agentforce after LogVisitAction to update
 * a Visit_Report__c with AI-extracted discussion topics and next best action.
 *
 * Use case: Agentforce analyses the transcript using Einstein and calls this
 * action to write back the structured output (topics, NBA, score) to the record.
 */
public with sharing class ExtractTopicsAction {

    // ─── INPUT / OUTPUT ────────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(required=true label='Visit Report ID')
        public Id visitReportId;

        @InvocableVariable(label='Extracted Discussion Topics')
        public String discussionTopics;

        @InvocableVariable(label='Next Best Action')
        public String nextBestAction;

        @InvocableVariable(label='AI Engagement Score (0-100)')
        public Decimal engagementScore;

        @InvocableVariable(label='AI Summary')
        public String aiSummary;

        @InvocableVariable(label='Needs Review Flag')
        public Boolean needsReview;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Updated Visit Report ID')
        public Id visitReportId;
    }

    // ─── INVOCABLE ENTRY POINT ─────────────────────────────────────────────────

    @InvocableMethod(
        label='Extract Topics & Update Visit Report'
        description='Updates an existing Visit_Report__c with AI-extracted topics, engagement score, next best action, and summary. Called by Agentforce after analysing the voice transcript.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        Set<Id> reportIds = new Set<Id>();
        for (Request req : requests) {
            if (req.visitReportId != null) {
                reportIds.add(req.visitReportId);
            }
        }

        Map<Id, Visit_Report__c> existingReports = new Map<Id, Visit_Report__c>(
            [SELECT Id FROM Visit_Report__c WHERE Id IN :reportIds]
        );

        List<Visit_Report__c> toUpdate = new List<Visit_Report__c>();
        List<Result> results = new List<Result>();
        List<Integer> updateIndexes = new List<Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = new Result();
            res.success = false;

            if (req.visitReportId == null || !existingReports.containsKey(req.visitReportId)) {
                res.errorMessage = 'Visit Report not found: ' + req.visitReportId;
                results.add(res);
                continue;
            }

            Visit_Report__c vr = new Visit_Report__c(Id = req.visitReportId);

            if (String.isNotBlank(req.discussionTopics)) {
                vr.Discussion_Topics__c = req.discussionTopics;
            }
            if (String.isNotBlank(req.nextBestAction)) {
                vr.Next_Best_Action__c = req.nextBestAction;
            }
            if (req.engagementScore != null) {
                vr.Engagement_Score__c = req.engagementScore;
            }
            if (String.isNotBlank(req.aiSummary)) {
                vr.AI_Summary__c = req.aiSummary;
            }
            if (req.needsReview != null) {
                vr.Needs_Review__c = req.needsReview;
            }

            toUpdate.add(vr);
            updateIndexes.add(i);
            res.visitReportId = req.visitReportId;
            results.add(res);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
            for (Integer j = 0; j < saveResults.size(); j++) {
                Database.SaveResult sr = saveResults[j];
                Result res = results[updateIndexes[j]];
                if (sr.isSuccess()) {
                    res.success = true;
                } else {
                    res.success = false;
                    res.errorMessage = sr.getErrors()[0].getMessage();
                }
            }
        }

        return results;
    }
}
