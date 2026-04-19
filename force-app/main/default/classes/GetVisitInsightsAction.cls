/**
 * GetVisitInsightsAction
 * @InvocableMethod — called by Agentforce BEFORE or AFTER logging a visit
 * to fetch rich context about a physician for NBA (Next Best Action) suggestions.
 *
 * Use case: Before the rep starts speaking, Agentforce calls this to prime
 * itself with the physician's history — last visit date, outcomes, relationship
 * score, and recent topics — so it can give smarter suggestions.
 */
public with sharing class GetVisitInsightsAction {

    private static final Integer MAX_RECENT_VISITS = 5;

    // ─── INPUT / OUTPUT ────────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(required=true label='Physician Account ID')
        public Id physicianId;
    }

    public class Result {
        @InvocableVariable(label='Physician Name')
        public String physicianName;

        @InvocableVariable(label='Specialty')
        public String specialty;

        @InvocableVariable(label='Territory')
        public String territory;

        @InvocableVariable(label='Relationship Score')
        public Decimal relationshipScore;

        @InvocableVariable(label='Total Visits')
        public Decimal totalVisits;

        @InvocableVariable(label='Last Visit Date')
        public Date lastVisitDate;

        @InvocableVariable(label='Last Visit Outcome')
        public String lastVisitOutcome;

        @InvocableVariable(label='Recent Topics (last 5 visits)')
        public String recentTopics;

        @InvocableVariable(label='Recent Outcomes Summary')
        public String recentOutcomesSummary;

        @InvocableVariable(label='Key Account')
        public Boolean isKeyAccount;

        @InvocableVariable(label='Preferred Visit Day')
        public String preferredVisitDay;

        @InvocableVariable(label='Preferred Visit Time')
        public String preferredVisitTime;

        @InvocableVariable(label='Context Summary for AI')
        public String contextSummaryForAI;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    // ─── INVOCABLE ENTRY POINT ─────────────────────────────────────────────────

    @InvocableMethod(
        label='Get Visit Insights for Physician'
        description='Returns rich visit history and physician profile data to help Agentforce generate smarter summaries and next best action recommendations.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        // Collect all physician IDs in one pass
        Set<Id> physicianIds = new Set<Id>();
        for (Request req : requests) {
            if (req.physicianId != null) {
                physicianIds.add(req.physicianId);
            }
        }

        // Single SOQL for account data
        Map<Id, Account> physicianMap = new Map<Id, Account>([
            SELECT Id, Name, Specialty__c, Territory__c, Relationship_Score__c,
                   Total_Visits__c, Last_Visit_Date__c, Key_Account__c,
                   Preferred_Visit_Day__c, Preferred_Visit_Time__c
            FROM Account
            WHERE Id IN :physicianIds
        ]);

        // Single SOQL for recent visit reports (all physicians at once)
        Map<Id, List<Visit_Report__c>> visitsByPhysician = new Map<Id, List<Visit_Report__c>>();
        for (Id pid : physicianIds) {
            visitsByPhysician.put(pid, new List<Visit_Report__c>());
        }

        for (Visit_Report__c vr : [
            SELECT Id, Physician__c, Visit_Date__c, Visit_Outcome__c,
                   Discussion_Topics__c, Engagement_Score__c, AI_Summary__c
            FROM Visit_Report__c
            WHERE Physician__c IN :physicianIds
            ORDER BY Visit_Date__c DESC NULLS LAST
            LIMIT 500
        ]) {
            List<Visit_Report__c> pvList = visitsByPhysician.get(vr.Physician__c);
            if (pvList != null && pvList.size() < MAX_RECENT_VISITS) {
                pvList.add(vr);
            }
        }

        // Build results
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result res = new Result();
            res.success = false;

            if (req.physicianId == null || !physicianMap.containsKey(req.physicianId)) {
                res.errorMessage = 'Physician not found: ' + req.physicianId;
                results.add(res);
                continue;
            }

            Account physician = physicianMap.get(req.physicianId);
            res.physicianName       = physician.Name;
            res.specialty           = physician.Specialty__c;
            res.territory           = physician.Territory__c;
            res.relationshipScore   = physician.Relationship_Score__c;
            res.totalVisits         = physician.Total_Visits__c;
            res.lastVisitDate       = physician.Last_Visit_Date__c;
            res.isKeyAccount        = physician.Key_Account__c;
            res.preferredVisitDay   = physician.Preferred_Visit_Day__c;
            res.preferredVisitTime  = physician.Preferred_Visit_Time__c;

            List<Visit_Report__c> recentVisits = visitsByPhysician.get(req.physicianId);
            if (!recentVisits.isEmpty()) {
                res.lastVisitOutcome = recentVisits[0].Visit_Outcome__c;
            }

            res.recentTopics = buildTopicsSummary(recentVisits);
            res.recentOutcomesSummary = buildOutcomesSummary(recentVisits);
            res.contextSummaryForAI = buildAIContext(physician, recentVisits);
            res.success = true;
            results.add(res);
        }

        return results;
    }

    // ─── HELPERS ──────────────────────────────────────────────────────────────

    private static String buildTopicsSummary(List<Visit_Report__c> visits) {
        List<String> topicParts = new List<String>();
        for (Visit_Report__c vr : visits) {
            if (String.isNotBlank(vr.Discussion_Topics__c)) {
                topicParts.add(vr.Discussion_Topics__c.abbreviate(200));
            }
        }
        return topicParts.isEmpty() ? 'No previous topics recorded.' : String.join(topicParts, ' | ');
    }

    private static String buildOutcomesSummary(List<Visit_Report__c> visits) {
        List<String> outcomeParts = new List<String>();
        for (Visit_Report__c vr : visits) {
            if (vr.Visit_Date__c != null && String.isNotBlank(vr.Visit_Outcome__c)) {
                outcomeParts.add(vr.Visit_Date__c.format() + ': ' + vr.Visit_Outcome__c);
            }
        }
        return outcomeParts.isEmpty() ? 'No previous visits.' : String.join(outcomeParts, '\n');
    }

    private static String buildAIContext(Account physician, List<Visit_Report__c> visits) {
        String ctx = 'Physician: ' + physician.Name;
        if (String.isNotBlank(physician.Specialty__c)) {
            ctx += ' | Specialty: ' + physician.Specialty__c;
        }
        ctx += ' | Relationship Score: ' + (physician.Relationship_Score__c != null ? String.valueOf(physician.Relationship_Score__c) : 'N/A');
        ctx += ' | Total Visits: ' + (physician.Total_Visits__c != null ? String.valueOf(physician.Total_Visits__c.intValue()) : '0');
        if (!visits.isEmpty()) {
            ctx += ' | Last Visit: ' + visits[0].Visit_Date__c?.format() + ' — ' + visits[0].Visit_Outcome__c;
        }
        if (String.isNotBlank(physician.Preferred_Visit_Day__c)) {
            ctx += ' | Prefers visits on: ' + physician.Preferred_Visit_Day__c;
        }
        return ctx;
    }
}
