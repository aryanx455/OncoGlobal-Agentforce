/**
 * Summarizes a rep's week/day for manager visibility.
 */
public with sharing class FieldManagerSummaryAction {

    public class Request {
        @InvocableVariable(label='Start Date YYYY-MM-DD')
        public String startDate;

        @InvocableVariable(label='End Date YYYY-MM-DD')
        public String endDate;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Summary Window')
        public String summaryWindow;

        @InvocableVariable(label='Visit Count')
        public Integer visitCount;

        @InvocableVariable(label='Typed Expense Count')
        public Integer typedExpenseCount;

        @InvocableVariable(label='Uploaded Expense Count')
        public Integer uploadedExpenseCount;

        @InvocableVariable(label='Flagged Expense Count')
        public Integer flaggedExpenseCount;

        @InvocableVariable(label='Open Task Count')
        public Integer openTaskCount;

        @InvocableVariable(label='High Potential Doctors')
        public String highPotentialDoctors;

        @InvocableVariable(label='Manager Summary')
        public String managerSummary;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Summarize Field Activity'
        description='Creates a manager-ready summary of visits, expenses, flagged bills, open tasks, and high-potential doctors.'
        category='OncoGlobal Health Cloud'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(summarize(req));
        }
        return results;
    }

    private static Result summarize(Request req) {
        Result res = new Result();
        res.success = false;

        try {
            Date startDate = parseDate(req == null ? null : req.startDate, Date.today().toStartOfWeek());
            Date endDate = parseDate(req == null ? null : req.endDate, Date.today());
            if (endDate < startDate) {
                Date temp = startDate;
                startDate = endDate;
                endDate = temp;
            }

            List<Visit_Report__c> visits = [
                SELECT Id, Name, Physician__r.Name, Visit_Date__c,
                       Visit_Outcome__c, Engagement_Score__c, Total_Expense_Amount__c
                FROM Visit_Report__c
                WHERE Visit_Date__c >= :startDate
                AND Visit_Date__c <= :endDate
                AND (Rep__c = :UserInfo.getUserId() OR OwnerId = :UserInfo.getUserId())
                ORDER BY Visit_Date__c DESC
                LIMIT 500
            ];

            Set<Id> visitIds = new Set<Id>();
            for (Visit_Report__c visit : visits) {
                visitIds.add(visit.Id);
            }

            List<Expense__c> typedExpenses = visitIds.isEmpty()
                ? new List<Expense__c>()
                : [
                    SELECT Id, Amount__c, Policy_Flag__c
                    FROM Expense__c
                    WHERE Visit_Report__c IN :visitIds
                    LIMIT 500
                ];

            List<Task> openTasks = [
                SELECT Id, Subject, ActivityDate
                FROM Task
                WHERE OwnerId = :UserInfo.getUserId()
                AND IsClosed = false
                ORDER BY ActivityDate ASC NULLS LAST
                LIMIT 100
            ];

            res.visitCount = visits.size();
            res.typedExpenseCount = typedExpenses.size();
            res.uploadedExpenseCount = 0;
            res.flaggedExpenseCount = countFlagged(typedExpenses);
            res.openTaskCount = openTasks.size();
            res.summaryWindow = startDate.format() + ' to ' + endDate.format();
            res.highPotentialDoctors = buildHighPotentialDoctors();
            res.managerSummary = buildManagerSummary(res, visits, openTasks);
            res.success = true;
        } catch (Exception e) {
            res.errorMessage = e.getMessage();
        }

        return res;
    }

    private static Integer countFlagged(List<Expense__c> expenses) {
        Integer count = 0;
        for (Expense__c expense : expenses) {
            if (expense.Policy_Flag__c == true) {
                count++;
            }
        }
        return count;
    }

    private static String buildHighPotentialDoctors() {
        List<String> names = new List<String>();
        for (Contact contact : [
            SELECT Name, Relationship_Score__c, Last_Visit_Date__c
            FROM Contact
            WHERE Prescribing_Potential__c = 'High'
            AND Do_Not_Visit__c = false
            ORDER BY Last_Visit_Date__c ASC NULLS FIRST
            LIMIT 5
        ]) {
            names.add(contact.Name + ' (score ' +
                (contact.Relationship_Score__c == null ? 'N/A' : String.valueOf(contact.Relationship_Score__c)) + ')');
        }
        return names.isEmpty() ? 'No high-potential doctors marked yet.' : String.join(names, '\n');
    }

    private static String buildManagerSummary(Result res, List<Visit_Report__c> visits, List<Task> openTasks) {
        List<String> parts = new List<String>();
        parts.add('Visits logged: ' + res.visitCount);
        parts.add('Typed expenses: ' + res.typedExpenseCount);
        parts.add('Uploaded expenses: ' + res.uploadedExpenseCount);
        parts.add('Flagged expenses: ' + res.flaggedExpenseCount);
        parts.add('Open follow-ups: ' + res.openTaskCount);

        if (!visits.isEmpty()) {
            Visit_Report__c latest = visits[0];
            String doctor = latest.Physician__r == null ? 'unknown doctor' : latest.Physician__r.Name;
            parts.add('Latest visit: ' + doctor + ' - ' + latest.Visit_Outcome__c);
        }
        if (!openTasks.isEmpty()) {
            parts.add('Next task: ' + openTasks[0].Subject);
        }

        return String.join(parts, '\n');
    }

    private static Date parseDate(String rawDate, Date fallbackDate) {
        if (String.isBlank(rawDate)) {
            return fallbackDate;
        }
        try {
            return Date.valueOf(rawDate);
        } catch (Exception e) {
            return fallbackDate;
        }
    }
}
