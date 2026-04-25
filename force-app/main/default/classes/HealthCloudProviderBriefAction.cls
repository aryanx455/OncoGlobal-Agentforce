/**
 * Read-only Agentforce action that builds a Health Cloud-first provider brief.
 *
 * The action prefers standard Health Cloud objects when records exist, then
 * falls back to the project's Account/Contact visit model so demos still work
 * with current data. It intentionally does not create or update records.
 */
public with sharing class HealthCloudProviderBriefAction {

    private static final Integer MAX_VISITS = 5;
    private static final Integer MAX_TASKS = 5;

    public class Request {
        @InvocableVariable(label='Doctor or Provider Name'
            description='Doctor/provider name as spoken by the rep. Do not ask the user for Salesforce IDs.')
        public String providerName;

        @InvocableVariable(label='Facility Name'
            description='Hospital, clinic, or facility name when the rep provides it.')
        public String facilityName;

        @InvocableVariable(label='Provider Account ID'
            description='Optional Account ID when the agent already has it from context.')
        public Id accountId;

        @InvocableVariable(label='Prescriber Contact ID'
            description='Optional Contact ID when the agent already has it from context.')
        public Id contactId;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Resolved Provider Name')
        public String providerName;

        @InvocableVariable(label='Provider Record ID')
        public String providerRecordId;

        @InvocableVariable(label='Provider Record Source')
        public String providerRecordSource;

        @InvocableVariable(label='Resolved Facility Name')
        public String facilityName;

        @InvocableVariable(label='Facility Record ID')
        public String facilityRecordId;

        @InvocableVariable(label='Facility Record Source')
        public String facilityRecordSource;

        @InvocableVariable(label='Standard Health Cloud Context')
        public String standardHealthCloudContext;

        @InvocableVariable(label='Relationship Snapshot')
        public String relationshipSnapshot;

        @InvocableVariable(label='Relationship Heat Score')
        public String relationshipHeatScore;

        @InvocableVariable(label='Recent Visit Summary')
        public String recentVisitSummary;

        @InvocableVariable(label='Open Task Summary')
        public String openTaskSummary;

        @InvocableVariable(label='Next Best Actions')
        public String nextBestActions;

        @InvocableVariable(label='Context Summary for Agent')
        public String contextSummaryForAgent;
    }

    private class ProviderMatch {
        Id healthcareProviderId;
        Id contactId;
        Id accountId;
        String name;
        String source;
        String healthCloudDetails;
        Contact contactRecord;
        Account accountRecord;
    }

    private class FacilityMatch {
        Id healthcareFacilityId;
        Id accountId;
        String name;
        String source;
        String healthCloudDetails;
        Account accountRecord;
    }

    @InvocableMethod(
        label='Get Health Cloud Provider Brief'
        description='Returns a provider brief using standard Health Cloud objects first, then existing Account/Contact visit history. Read-only and safe for pre-visit planning.'
        category='OncoGlobal Health Cloud'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(buildBrief(req));
        }
        return results;
    }

    private static Result buildBrief(Request req) {
        Result res = new Result();
        res.success = false;

        try {
            if (req == null || (String.isBlank(req.providerName) && req.accountId == null && req.contactId == null)) {
                res.errorMessage = 'Provider name or provider context is required.';
                return res;
            }

            ProviderMatch provider = resolveProvider(req);
            if (provider == null) {
                res.errorMessage = 'No matching provider found for: ' + req.providerName;
                return res;
            }

            FacilityMatch facility = resolveFacility(req, provider);
            List<Visit_Report__c> visits = findRecentVisits(provider, facility);
            List<Task> tasks = findOpenTasks(provider, visits);

            res.success = true;
            res.providerName = provider.name;
            res.providerRecordId = firstNonBlankId(provider.healthcareProviderId, provider.contactId, provider.accountId);
            res.providerRecordSource = provider.source;
            res.facilityName = facility == null ? null : facility.name;
            res.facilityRecordId = facility == null ? null : firstNonBlankId(facility.healthcareFacilityId, facility.accountId, null);
            res.facilityRecordSource = facility == null ? null : facility.source;
            res.standardHealthCloudContext = buildHealthCloudContext(provider, facility);
            res.relationshipSnapshot = buildRelationshipSnapshot(provider);
            res.recentVisitSummary = buildRecentVisitSummary(visits);
            res.openTaskSummary = buildOpenTaskSummary(tasks);
            res.relationshipHeatScore = buildRelationshipHeatScore(provider, visits, tasks);
            res.nextBestActions = buildNextBestActions(provider, visits, tasks);
            res.contextSummaryForAgent = buildAgentContext(res);
        } catch (Exception e) {
            res.success = false;
            res.errorMessage = e.getMessage();
        }

        return res;
    }

    private static ProviderMatch resolveProvider(Request req) {
        ProviderMatch byContext = resolveProviderFromContext(req);
        if (byContext != null) {
            return byContext;
        }

        String searchName = cleanName(req.providerName);
        if (String.isBlank(searchName)) {
            return null;
        }

        ProviderMatch healthCloudProvider = findHealthcareProvider(searchName);
        if (healthCloudProvider != null) {
            enrichProviderFromStandardLookups(healthCloudProvider);
            return healthCloudProvider;
        }

        ProviderMatch contactProvider = findContactProvider(searchName);
        if (contactProvider != null) {
            return contactProvider;
        }

        return findAccountProvider(searchName);
    }

    private static ProviderMatch resolveProviderFromContext(Request req) {
        if (req.contactId != null) {
            List<Contact> contacts = [
                SELECT Id, Name, AccountId, Specialty__c, Relationship_Score__c,
                       Engagement_Score__c, Total_Visits__c, Last_Visit_Date__c,
                       Influence_Level__c, Prescribing_Potential__c
                FROM Contact
                WHERE Id = :req.contactId
                LIMIT 1
            ];
            if (!contacts.isEmpty()) {
                ProviderMatch match = new ProviderMatch();
                match.contactId = contacts[0].Id;
                match.accountId = contacts[0].AccountId;
                match.name = contacts[0].Name;
                match.source = 'Contact';
                match.contactRecord = contacts[0];
                match.accountRecord = findAccountById(contacts[0].AccountId);
                return match;
            }
        }

        if (req.accountId != null) {
            Account account = findAccountById(req.accountId);
            if (account != null) {
                ProviderMatch match = new ProviderMatch();
                match.accountId = account.Id;
                match.name = account.Name;
                match.source = 'Account';
                match.accountRecord = account;
                return match;
            }
        }

        return null;
    }

    private static ProviderMatch findHealthcareProvider(String searchName) {
        if (!Schema.getGlobalDescribe().containsKey('HealthcareProvider')) {
            return null;
        }

        String wildcard = '%' + searchName + '%';
        List<SObject> rows = Database.query(
            'SELECT Id, Name, AccountId, PractitionerId, ProviderType, ProviderClass, ' +
            'ProfessionalTitle, Status FROM HealthcareProvider ' +
            'WHERE Name LIKE :wildcard ORDER BY LastModifiedDate DESC LIMIT 1'
        );
        if (rows.isEmpty()) {
            return null;
        }

        SObject row = rows[0];
        ProviderMatch match = new ProviderMatch();
        match.healthcareProviderId = (Id) row.get('Id');
        match.accountId = (Id) row.get('AccountId');
        match.contactId = (Id) row.get('PractitionerId');
        match.name = valueOf(row.get('Name'));
        match.source = 'HealthcareProvider';
        match.healthCloudDetails = joinNonBlank(new List<String>{
            labelValue('Provider Type', row.get('ProviderType')),
            labelValue('Provider Class', row.get('ProviderClass')),
            labelValue('Professional Title', row.get('ProfessionalTitle')),
            labelValue('Status', row.get('Status'))
        }, ' | ');
        return match;
    }

    private static void enrichProviderFromStandardLookups(ProviderMatch match) {
        if (match.contactId != null) {
            List<Contact> contacts = [
                SELECT Id, Name, AccountId, Specialty__c, Relationship_Score__c,
                       Engagement_Score__c, Total_Visits__c, Last_Visit_Date__c,
                       Influence_Level__c, Prescribing_Potential__c
                FROM Contact
                WHERE Id = :match.contactId
                LIMIT 1
            ];
            if (!contacts.isEmpty()) {
                match.contactRecord = contacts[0];
                if (match.accountId == null) {
                    match.accountId = contacts[0].AccountId;
                }
            }
        }
        if (match.accountRecord == null && match.accountId != null) {
            match.accountRecord = findAccountById(match.accountId);
        }
    }

    private static ProviderMatch findContactProvider(String searchName) {
        String wildcard = '%' + searchName + '%';
        List<Contact> contacts = [
            SELECT Id, Name, AccountId, Specialty__c, Relationship_Score__c,
                   Engagement_Score__c, Total_Visits__c, Last_Visit_Date__c,
                   Influence_Level__c, Prescribing_Potential__c
            FROM Contact
            WHERE Name LIKE :wildcard
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            return null;
        }

        ProviderMatch match = new ProviderMatch();
        match.contactId = contacts[0].Id;
        match.accountId = contacts[0].AccountId;
        match.name = contacts[0].Name;
        match.source = 'Contact';
        match.contactRecord = contacts[0];
        match.accountRecord = findAccountById(contacts[0].AccountId);
        return match;
    }

    private static ProviderMatch findAccountProvider(String searchName) {
        String wildcard = '%' + searchName + '%';
        List<Account> accounts = [
            SELECT Id, Name, Specialty__c, Territory__c, Relationship_Score__c,
                   Total_Visits__c, Last_Visit_Date__c, Key_Account__c,
                   Preferred_Visit_Day__c, Preferred_Visit_Time__c, Facility_Type__c
            FROM Account
            WHERE Name LIKE :wildcard
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return null;
        }

        ProviderMatch match = new ProviderMatch();
        match.accountId = accounts[0].Id;
        match.name = accounts[0].Name;
        match.source = 'Account';
        match.accountRecord = accounts[0];
        return match;
    }

    private static Account findAccountById(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<Account> accounts = [
            SELECT Id, Name, Specialty__c, Territory__c, Relationship_Score__c,
                   Total_Visits__c, Last_Visit_Date__c, Key_Account__c,
                   Preferred_Visit_Day__c, Preferred_Visit_Time__c, Facility_Type__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    private static FacilityMatch resolveFacility(Request req, ProviderMatch provider) {
        String searchName = cleanName(req.facilityName);
        if (String.isNotBlank(searchName)) {
            FacilityMatch healthCloudFacility = findHealthcareFacilityByName(searchName);
            if (healthCloudFacility != null) {
                return healthCloudFacility;
            }

            FacilityMatch accountFacility = findFacilityAccountByName(searchName);
            if (accountFacility != null) {
                return accountFacility;
            }
        }

        FacilityMatch fromProvider = findFacilityFromPractitionerFacility(provider);
        if (fromProvider != null) {
            return fromProvider;
        }

        if (provider != null && provider.accountRecord != null) {
            FacilityMatch match = new FacilityMatch();
            match.accountId = provider.accountRecord.Id;
            match.name = provider.accountRecord.Name;
            match.source = 'Account';
            match.accountRecord = provider.accountRecord;
            return match;
        }

        return null;
    }

    private static FacilityMatch findHealthcareFacilityByName(String searchName) {
        if (!Schema.getGlobalDescribe().containsKey('HealthcareFacility')) {
            return null;
        }

        String wildcard = '%' + searchName + '%';
        List<SObject> rows = Database.query(
            'SELECT Id, Name, AccountId, HealthcareProviderId, LocationType, IsAlwaysOpen, LicensedBedCount ' +
            'FROM HealthcareFacility WHERE Name LIKE :wildcard ORDER BY LastModifiedDate DESC LIMIT 1'
        );
        return rows.isEmpty() ? null : buildFacilityMatch(rows[0]);
    }

    private static FacilityMatch findFacilityFromPractitionerFacility(ProviderMatch provider) {
        if (provider == null || provider.healthcareProviderId == null ||
                !Schema.getGlobalDescribe().containsKey('HealthcarePractitionerFacility')) {
            return null;
        }

        Id healthcareProviderId = provider.healthcareProviderId;
        List<SObject> links = Database.query(
            'SELECT HealthcareFacilityId FROM HealthcarePractitionerFacility ' +
            'WHERE HealthcareProviderId = :healthcareProviderId AND IsActive = true ' +
            'ORDER BY LastModifiedDate DESC LIMIT 1'
        );
        if (links.isEmpty()) {
            return null;
        }

        Id facilityId = (Id) links[0].get('HealthcareFacilityId');
        List<SObject> facilities = Database.query(
            'SELECT Id, Name, AccountId, HealthcareProviderId, LocationType, IsAlwaysOpen, LicensedBedCount ' +
            'FROM HealthcareFacility WHERE Id = :facilityId LIMIT 1'
        );
        return facilities.isEmpty() ? null : buildFacilityMatch(facilities[0]);
    }

    private static FacilityMatch buildFacilityMatch(SObject row) {
        FacilityMatch match = new FacilityMatch();
        match.healthcareFacilityId = (Id) row.get('Id');
        match.accountId = (Id) row.get('AccountId');
        match.name = valueOf(row.get('Name'));
        match.source = 'HealthcareFacility';
        match.accountRecord = findAccountById(match.accountId);
        match.healthCloudDetails = joinNonBlank(new List<String>{
            labelValue('Location Type', row.get('LocationType')),
            labelValue('Always Open', row.get('IsAlwaysOpen')),
            labelValue('Licensed Beds', row.get('LicensedBedCount'))
        }, ' | ');
        return match;
    }

    private static FacilityMatch findFacilityAccountByName(String searchName) {
        String wildcard = '%' + searchName + '%';
        List<Account> accounts = [
            SELECT Id, Name, Specialty__c, Territory__c, Relationship_Score__c,
                   Total_Visits__c, Last_Visit_Date__c, Key_Account__c,
                   Preferred_Visit_Day__c, Preferred_Visit_Time__c, Facility_Type__c
            FROM Account
            WHERE Name LIKE :wildcard
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return null;
        }

        FacilityMatch match = new FacilityMatch();
        match.accountId = accounts[0].Id;
        match.name = accounts[0].Name;
        match.source = 'Account';
        match.accountRecord = accounts[0];
        return match;
    }

    private static List<Visit_Report__c> findRecentVisits(ProviderMatch provider, FacilityMatch facility) {
        List<String> conditions = new List<String>();
        Map<String, Schema.SObjectField> visitFields = Schema.SObjectType.Visit_Report__c.fields.getMap();
        if (provider != null && provider.contactId != null && visitFields.containsKey('Prescriber__c')) {
            conditions.add('Prescriber__c = \'' + String.escapeSingleQuotes(String.valueOf(provider.contactId)) + '\'');
        }
        if (provider != null && provider.accountId != null) {
            conditions.add('Physician__c = \'' + String.escapeSingleQuotes(String.valueOf(provider.accountId)) + '\'');
        }
        if (facility != null && facility.accountId != null && visitFields.containsKey('Hospital__c')) {
            conditions.add('Hospital__c = \'' + String.escapeSingleQuotes(String.valueOf(facility.accountId)) + '\'');
        }
        if (conditions.isEmpty()) {
            return new List<Visit_Report__c>();
        }

        String query =
            'SELECT Id, Name, Visit_Date__c, Visit_Outcome__c, Discussion_Topics__c, ' +
            'AI_Summary__c, Engagement_Score__c, Next_Best_Action__c, Total_Visit_Expense__c ' +
            'FROM Visit_Report__c WHERE ' + String.join(conditions, ' OR ') +
            ' ORDER BY Visit_Date__c DESC NULLS LAST, CreatedDate DESC LIMIT ' + MAX_VISITS;
        return Database.query(query);
    }

    private static List<Task> findOpenTasks(ProviderMatch provider, List<Visit_Report__c> visits) {
        Set<Id> visitIds = new Set<Id>();
        for (Visit_Report__c visit : visits) {
            visitIds.add(visit.Id);
        }

        List<String> conditions = new List<String>();
        if (!visitIds.isEmpty()) {
            List<String> quotedVisitIds = new List<String>();
            for (Id visitId : visitIds) {
                quotedVisitIds.add('\'' + String.escapeSingleQuotes(String.valueOf(visitId)) + '\'');
            }
            conditions.add('WhatId IN (' + String.join(quotedVisitIds, ',') + ')');
        }
        if (provider != null && provider.contactId != null) {
            conditions.add('WhoId = \'' + String.escapeSingleQuotes(String.valueOf(provider.contactId)) + '\'');
        }
        if (conditions.isEmpty()) {
            return new List<Task>();
        }

        String query =
            'SELECT Id, Subject, ActivityDate, Status, Priority FROM Task ' +
            'WHERE IsClosed = false AND (' + String.join(conditions, ' OR ') + ') ' +
            'ORDER BY ActivityDate ASC NULLS LAST, CreatedDate DESC LIMIT ' + MAX_TASKS;
        return Database.query(query);
    }

    private static String buildHealthCloudContext(ProviderMatch provider, FacilityMatch facility) {
        List<String> parts = new List<String>();
        if (provider != null && provider.healthcareProviderId != null) {
            parts.add('HealthcareProvider found: ' + provider.name + ' (' + provider.healthcareProviderId + ')');
            if (String.isNotBlank(provider.healthCloudDetails)) {
                parts.add(provider.healthCloudDetails);
            }
        } else {
            parts.add('No HealthcareProvider match found; using ' + provider.source + ' fallback.');
        }

        if (facility != null && facility.healthcareFacilityId != null) {
            parts.add('HealthcareFacility found: ' + facility.name + ' (' + facility.healthcareFacilityId + ')');
            if (String.isNotBlank(facility.healthCloudDetails)) {
                parts.add(facility.healthCloudDetails);
            }
        } else if (facility != null) {
            parts.add('Facility context from ' + facility.source + ': ' + facility.name);
        }

        return String.join(parts, '\n');
    }

    private static String buildRelationshipSnapshot(ProviderMatch provider) {
        List<String> parts = new List<String>();
        if (provider.contactRecord != null) {
            parts.add(labelValue('Specialty', provider.contactRecord.Specialty__c));
            parts.add(labelValue('Relationship Score', provider.contactRecord.Relationship_Score__c));
            parts.add(labelValue('Engagement Score', provider.contactRecord.Engagement_Score__c));
            parts.add(labelValue('Total Visits', provider.contactRecord.Total_Visits__c));
            parts.add(labelValue('Last Visit', provider.contactRecord.Last_Visit_Date__c));
            parts.add(labelValue('Influence', provider.contactRecord.Influence_Level__c));
            parts.add(labelValue('Prescribing Potential', provider.contactRecord.Prescribing_Potential__c));
        }
        if (provider.accountRecord != null) {
            parts.add(labelValue('Territory', provider.accountRecord.Territory__c));
            parts.add(labelValue('Account Relationship Score', provider.accountRecord.Relationship_Score__c));
            parts.add(labelValue('Account Visits', provider.accountRecord.Total_Visits__c));
            parts.add(labelValue('Preferred Day', provider.accountRecord.Preferred_Visit_Day__c));
            parts.add(labelValue('Preferred Time', provider.accountRecord.Preferred_Visit_Time__c));
            parts.add(labelValue('Facility Type', provider.accountRecord.Facility_Type__c));
        }

        List<String> nonBlank = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                nonBlank.add(part);
            }
        }
        return nonBlank.isEmpty() ? 'No relationship metrics recorded yet.' : String.join(nonBlank, ' | ');
    }

    private static String buildRecentVisitSummary(List<Visit_Report__c> visits) {
        if (visits.isEmpty()) {
            return 'No recent visits found.';
        }

        List<String> rows = new List<String>();
        for (Visit_Report__c visit : visits) {
            List<String> rowParts = new List<String>();
            rowParts.add(visit.Visit_Date__c == null ? 'No date' : visit.Visit_Date__c.format());
            rowParts.add(String.isBlank(visit.Visit_Outcome__c) ? 'Outcome not captured' : visit.Visit_Outcome__c);
            if (String.isNotBlank(visit.AI_Summary__c)) {
                rowParts.add(visit.AI_Summary__c.abbreviate(180));
            } else if (String.isNotBlank(visit.Discussion_Topics__c)) {
                rowParts.add(visit.Discussion_Topics__c.abbreviate(180));
            }
            if (String.isNotBlank(visit.Next_Best_Action__c)) {
                rowParts.add('Next: ' + visit.Next_Best_Action__c.abbreviate(120));
            }
            rows.add('- ' + String.join(rowParts, ' | '));
        }
        return String.join(rows, '\n');
    }

    private static String buildRelationshipHeatScore(ProviderMatch provider, List<Visit_Report__c> visits, List<Task> tasks) {
        Integer score = 50;
        List<String> reasons = new List<String>();

        Decimal relationshipScore = null;
        if (provider.contactRecord != null && provider.contactRecord.Relationship_Score__c != null) {
            relationshipScore = provider.contactRecord.Relationship_Score__c;
        } else if (provider.accountRecord != null && provider.accountRecord.Relationship_Score__c != null) {
            relationshipScore = provider.accountRecord.Relationship_Score__c;
        }
        if (relationshipScore != null) {
            score = Integer.valueOf(relationshipScore);
            reasons.add('relationship score ' + score);
        }

        if (!visits.isEmpty() && visits[0].Visit_Date__c != null) {
            Integer daysSinceVisit = visits[0].Visit_Date__c.daysBetween(Date.today());
            if (daysSinceVisit <= 14) {
                score += 10;
                reasons.add('recent visit within 14 days');
            } else if (daysSinceVisit > 45) {
                score -= 15;
                reasons.add('no recent visit in 45+ days');
            }
        } else {
            score -= 10;
            reasons.add('no visit history');
        }

        if (!tasks.isEmpty()) {
            score -= Math.min(15, tasks.size() * 3);
            reasons.add(tasks.size() + ' open follow-up task(s)');
        }

        score = Math.max(0, Math.min(100, score));
        String band = score >= 75 ? 'Hot' : score >= 55 ? 'Warm' : score >= 35 ? 'Cold' : 'Needs Attention';
        return band + ' (' + score + '/100)' + (reasons.isEmpty() ? '' : ' - ' + String.join(reasons, ', '));
    }

    private static String buildOpenTaskSummary(List<Task> tasks) {
        if (tasks.isEmpty()) {
            return 'No open follow-up tasks found.';
        }

        List<String> rows = new List<String>();
        for (Task task : tasks) {
            rows.add('- ' + task.Subject + ' | ' + task.Status + ' | due ' +
                (task.ActivityDate == null ? 'not set' : task.ActivityDate.format()));
        }
        return String.join(rows, '\n');
    }

    private static String buildNextBestActions(ProviderMatch provider, List<Visit_Report__c> visits, List<Task> tasks) {
        List<String> actions = new List<String>();
        if (!tasks.isEmpty()) {
            actions.add('Close or update the oldest open follow-up before creating new commitments.');
        }
        if (visits.isEmpty()) {
            actions.add('Log the first visit with a clear objective, outcome, and follow-up task.');
        } else {
            Visit_Report__c lastVisit = visits[0];
            if (String.isNotBlank(lastVisit.Next_Best_Action__c)) {
                actions.add('Continue the previous next best action: ' + lastVisit.Next_Best_Action__c.abbreviate(180));
            }
            if (lastVisit.Visit_Date__c != null && lastVisit.Visit_Date__c.daysBetween(Date.today()) > 30) {
                actions.add('Relationship is getting stale; schedule a check-in visit.');
            }
        }

        Decimal score = null;
        if (provider.contactRecord != null && provider.contactRecord.Relationship_Score__c != null) {
            score = provider.contactRecord.Relationship_Score__c;
        } else if (provider.accountRecord != null && provider.accountRecord.Relationship_Score__c != null) {
            score = provider.accountRecord.Relationship_Score__c;
        }
        if (score != null && score < 50) {
            actions.add('Use a low-friction visit objective and ask what support would be useful.');
        }

        return actions.isEmpty()
            ? 'Maintain relationship momentum and capture any expense immediately after the visit.'
            : String.join(actions, '\n');
    }

    private static String buildAgentContext(Result res) {
        return joinNonBlank(new List<String>{
            'Provider: ' + res.providerName + ' via ' + res.providerRecordSource,
            String.isBlank(res.facilityName) ? null : 'Facility: ' + res.facilityName + ' via ' + res.facilityRecordSource,
            res.relationshipSnapshot,
            res.relationshipHeatScore,
            res.recentVisitSummary,
            res.openTaskSummary,
            res.nextBestActions
        }, '\n');
    }

    private static String cleanName(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        return raw.replaceAll('(?i)^dr\\.?\\s+', '').trim();
    }

    private static String firstNonBlankId(Id firstId, Id secondId, Id thirdId) {
        if (firstId != null) return String.valueOf(firstId);
        if (secondId != null) return String.valueOf(secondId);
        if (thirdId != null) return String.valueOf(thirdId);
        return null;
    }

    private static String labelValue(String label, Object value) {
        String text = valueOf(value);
        return String.isBlank(text) ? null : label + ': ' + text;
    }

    private static String valueOf(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String joinNonBlank(List<String> values, String separator) {
        List<String> nonBlank = new List<String>();
        for (String value : values) {
            if (String.isNotBlank(value)) {
                nonBlank.add(value);
            }
        }
        return String.join(nonBlank, separator);
    }
}
