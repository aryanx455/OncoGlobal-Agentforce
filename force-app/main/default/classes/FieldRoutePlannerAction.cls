/**
 * Builds a mobile-friendly route plan using standard Account/Contact/Task data
 * plus existing visit history. Health Cloud objects are acknowledged through
 * provider/facility availability but the action avoids hardcoded records.
 */
public with sharing class FieldRoutePlannerAction {

    private static final Integer DEFAULT_MAX_STOPS = 5;

    public class Request {
        @InvocableVariable(label='Territory')
        public String territory;

        @InvocableVariable(label='Planned Date YYYY-MM-DD')
        public String plannedDate;

        @InvocableVariable(label='Maximum Stops')
        public Integer maxStops;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Route Date')
        public String routeDate;

        @InvocableVariable(label='Territory')
        public String territory;

        @InvocableVariable(label='Recommended Stops')
        public String recommendedStops;

        @InvocableVariable(label='Route Summary')
        public String routeSummary;

        @InvocableVariable(label='Standard Object Usage')
        public String standardObjectUsage;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    private class Candidate {
        Contact contact;
        Account account;
        Date lastVisitDate;
        Integer openTaskCount = 0;
        Integer score = 0;
        List<String> reasons = new List<String>();
    }

    @InvocableMethod(
        label='Plan Field Route'
        description='Suggests doctors to visit based on Account, Contact, Task, Health Cloud availability, and Visit_Report__c history.'
        category='OncoGlobal Health Cloud'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(plan(req));
        }
        return results;
    }

    private static Result plan(Request req) {
        Result res = new Result();
        res.success = false;

        try {
            Date routeDate = parseDate(req == null ? null : req.plannedDate);
            Integer maxStops = req != null && req.maxStops != null && req.maxStops > 0
                ? Math.min(req.maxStops, 10)
                : DEFAULT_MAX_STOPS;
            String territory = req == null ? null : req.territory;

            List<Candidate> candidates = buildCandidates(territory);
            scoreCandidates(candidates);
            candidates.sort(new CandidateSorter());

            List<String> stopRows = new List<String>();
            Integer stopNumber = 1;
            for (Candidate candidate : candidates) {
                if (stopNumber > maxStops) {
                    break;
                }
                stopRows.add(formatStop(stopNumber, candidate));
                stopNumber++;
            }

            res.success = true;
            res.routeDate = String.valueOf(routeDate);
            res.territory = String.isBlank(territory) ? 'All territories' : territory;
            res.recommendedStops = stopRows.isEmpty()
                ? 'No eligible doctors found for this route.'
                : String.join(stopRows, '\n');
            res.routeSummary = 'Planned ' + String.valueOf(stopRows.size()) + ' stop(s) for ' + res.territory +
                '. Prioritized stale relationships, high potential doctors, and open follow-ups.';
            res.standardObjectUsage = buildStandardObjectUsage();
        } catch (Exception e) {
            res.errorMessage = e.getMessage();
        }

        return res;
    }

    private static List<Candidate> buildCandidates(String territory) {
        String wildcardTerritory = String.isBlank(territory) ? null : '%' + territory.trim() + '%';
        List<Contact> contacts;
        if (String.isBlank(wildcardTerritory)) {
            contacts = [
                SELECT Id, Name, AccountId, Account.Name, Account.Territory__c,
                       Specialty__c, Relationship_Score__c, Engagement_Score__c,
                       Total_Visits__c, Last_Visit_Date__c, Prescribing_Potential__c,
                       Do_Not_Visit__c
                FROM Contact
                WHERE Do_Not_Visit__c = false
                ORDER BY LastModifiedDate DESC
                LIMIT 100
            ];
        } else {
            contacts = [
                SELECT Id, Name, AccountId, Account.Name, Account.Territory__c,
                       Specialty__c, Relationship_Score__c, Engagement_Score__c,
                       Total_Visits__c, Last_Visit_Date__c, Prescribing_Potential__c,
                       Do_Not_Visit__c
                FROM Contact
                WHERE Do_Not_Visit__c = false
                AND Account.Territory__c LIKE :wildcardTerritory
                ORDER BY LastModifiedDate DESC
                LIMIT 100
            ];
        }

        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Map<Id, Candidate> byContact = new Map<Id, Candidate>();
        for (Contact contact : contacts) {
            Candidate candidate = new Candidate();
            candidate.contact = contact;
            candidate.account = contact.Account;
            candidate.lastVisitDate = contact.Last_Visit_Date__c;
            byContact.put(contact.Id, candidate);
            contactIds.add(contact.Id);
            if (contact.AccountId != null) {
                accountIds.add(contact.AccountId);
            }
        }

        for (AggregateResult ar : [
            SELECT WhoId whoId, COUNT(Id) taskCount
            FROM Task
            WHERE IsClosed = false
            AND WhoId IN :contactIds
            GROUP BY WhoId
        ]) {
            Candidate candidate = byContact.get((Id) ar.get('whoId'));
            if (candidate != null) {
                candidate.openTaskCount = Integer.valueOf(ar.get('taskCount'));
            }
        }

        for (Visit_Report__c visit : [
            SELECT Prescriber__c, Visit_Date__c
            FROM Visit_Report__c
            WHERE Prescriber__c IN :contactIds
            ORDER BY Visit_Date__c DESC NULLS LAST
            LIMIT 500
        ]) {
            Candidate candidate = byContact.get(visit.Prescriber__c);
            if (candidate != null && candidate.lastVisitDate == null) {
                candidate.lastVisitDate = visit.Visit_Date__c;
            }
        }

        return byContact.values();
    }

    private static void scoreCandidates(List<Candidate> candidates) {
        for (Candidate candidate : candidates) {
            candidate.score = 50;

            if (candidate.lastVisitDate == null) {
                candidate.score += 20;
                candidate.reasons.add('no visit history');
            } else {
                Integer daysSinceVisit = candidate.lastVisitDate.daysBetween(Date.today());
                if (daysSinceVisit > 45) {
                    candidate.score += 25;
                    candidate.reasons.add(daysSinceVisit + ' days since last visit');
                } else if (daysSinceVisit > 21) {
                    candidate.score += 12;
                    candidate.reasons.add(daysSinceVisit + ' days since last visit');
                }
            }

            if (candidate.openTaskCount > 0) {
                candidate.score += Math.min(20, candidate.openTaskCount * 5);
                candidate.reasons.add(candidate.openTaskCount + ' open follow-up task(s)');
            }

            if ('High'.equalsIgnoreCase(candidate.contact.Prescribing_Potential__c)) {
                candidate.score += 15;
                candidate.reasons.add('high prescribing potential');
            }

            if (candidate.contact.Relationship_Score__c != null && candidate.contact.Relationship_Score__c < 50) {
                candidate.score += 8;
                candidate.reasons.add('relationship needs attention');
            }
        }
    }

    private static String formatStop(Integer stopNumber, Candidate candidate) {
        String facility = candidate.account == null || String.isBlank(candidate.account.Name)
            ? 'facility not set'
            : candidate.account.Name;
        String lastVisit = candidate.lastVisitDate == null ? 'never visited' : 'last visit ' + candidate.lastVisitDate.format();
        return String.valueOf(stopNumber) + '. ' + candidate.contact.Name + ' @ ' + facility +
            ' - score ' + candidate.score + ', ' + lastVisit +
            (candidate.reasons.isEmpty() ? '' : ', because ' + String.join(candidate.reasons, ', '));
    }

    private static String buildStandardObjectUsage() {
        List<String> objects = new List<String>{ 'Contact', 'Account', 'Task', 'Event' };
        if (Schema.getGlobalDescribe().containsKey('HealthcareProvider')) {
            objects.add('HealthcareProvider');
        }
        if (Schema.getGlobalDescribe().containsKey('HealthcareFacility')) {
            objects.add('HealthcareFacility');
        }
        if (Schema.getGlobalDescribe().containsKey('ServiceAppointment')) {
            objects.add('ServiceAppointment');
        }
        return 'Uses standard objects: ' + String.join(objects, ', ') + '. Uses Visit_Report__c only for existing visit history.';
    }

    private static Date parseDate(String rawDate) {
        if (String.isBlank(rawDate)) {
            return Date.today().addDays(1);
        }
        try {
            return Date.valueOf(rawDate);
        } catch (Exception e) {
            return Date.today().addDays(1);
        }
    }

    private class CandidateSorter implements Comparator<Candidate> {
        public Integer compare(Candidate left, Candidate right) {
            return right.score - left.score;
        }
    }
}
