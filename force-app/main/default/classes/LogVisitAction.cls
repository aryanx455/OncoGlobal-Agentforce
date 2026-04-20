/**
 * LogVisitAction
 * @InvocableMethod — called by Agentforce PostVisitLogAgent to create a
 * Visit_Report__c from a voice transcript captured on the mobile LWC.
 *
 * Accepts either a Salesforce Account ID (physicianId) or a plain-language
 * physician name (physicianName) + optional hospital name. When only a name
 * is supplied the action resolves it to an Account via SOQL.
 */
public without sharing class LogVisitAction {

    // ─── INPUT / OUTPUT ────────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(label='Voice Transcript'
            description='The full voice transcript or summary spoken by the rep after the visit. REQUIRED — this is the main input for the agent.')
        public String transcript;

        @InvocableVariable(label='Physician Name'
            description='Name of the physician as spoken by the rep (e.g. "Dr. Sharma", "Dr. Meena Nair"). Used to look up the Account when Physician Account ID is not available. Provide this if you do not have the Physician Account ID.')
        public String physicianName;

        @InvocableVariable(label='Hospital or Facility Name'
            description='Name of the hospital or clinic where the visit took place (e.g. "Apollo Mumbai", "Tata Memorial", "Manipal Bangalore"). Helps narrow down the physician search.')
        public String hospitalName;

        @InvocableVariable(label='Physician Account ID'
            description='Salesforce Account ID of the physician. Optional — if not provided, Physician Name will be used to look up the Account.')
        public Id physicianId;

        @InvocableVariable(label='Visit Outcome'
            description='One of: Positive, Negative, Neutral, Follow-Up Required. Default is Neutral.')
        public String visitOutcome;

        @InvocableVariable(label='Visit Type'
            description='One of: In-Person Clinic, Hospital Round, Virtual Call, Conference / Event, Drop-In. Default is In-Person Clinic.')
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

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Visit Report Name')
        public String visitReportName;

        @InvocableVariable(label='Physician Name (resolved)')
        public String resolvedPhysicianName;

        @InvocableVariable(label='Prescriber Contact ID')
        public Id prescriberContactId;

        @InvocableVariable(label='Hospital Account ID')
        public Id hospitalAccountId;
    }

    // ─── INVOCABLE ENTRY POINT ─────────────────────────────────────────────────

    @InvocableMethod(
        label='Log Post-Visit Report'
        description='Creates a Visit_Report__c record from a voice transcript. Accepts physician name (e.g. "Dr. Sharma") and hospital name (e.g. "Apollo Mumbai") — no Salesforce IDs needed. Called by Agentforce after rep speaks their visit summary.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Visit_Report__c> reportsToInsert = new List<Visit_Report__c>();
        List<Result> results = new List<Result>();
        List<Integer> validIndexes = new List<Integer>();
        Map<Id, String> accountNamesById = new Map<Id, String>();
        Set<Id> physicianIdsToQuery = new Set<Id>();
        Map<String, Id> resolvedPhysicianIdsByKey = new Map<String, Id>();
        // Contact resolution cache: resolutionKey → [contactId, accountId]
        Map<String, Id[]> resolvedContactByKey = new Map<String, Id[]>();

        for (Request req : requests) {
            if (req != null && req.physicianId != null) {
                physicianIdsToQuery.add(req.physicianId);
            }
        }

        if (!physicianIdsToQuery.isEmpty()) {
            for (Account acc : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :physicianIdsToQuery
            ]) {
                accountNamesById.put(acc.Id, acc.Name);
            }
        }

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = new Result();
            res.success = false;

            if (String.isBlank(req.transcript)) {
                res.errorMessage = 'Transcript is required.';
                results.add(res);
                continue;
            }

            // ── Resolve prescriber Contact first, fall back to Account ────────
            Id resolvedPhysicianId = req.physicianId;
            Id prescriberContactId = null;
            Id hospitalAccountId   = null;
            String resolutionKey   = buildResolutionKey(req.physicianName, req.hospitalName);

            if (String.isNotBlank(resolutionKey)) {
                if (resolvedContactByKey.containsKey(resolutionKey)) {
                    Id[] cached = resolvedContactByKey.get(resolutionKey);
                    prescriberContactId = cached[0];
                    hospitalAccountId   = cached[1];
                } else {
                    Contact found = resolveContact(req.physicianName, req.hospitalName);
                    if (found != null) {
                        prescriberContactId = found.Id;
                        hospitalAccountId   = found.AccountId;
                        res.resolvedPhysicianName = found.Name;
                    }
                    resolvedContactByKey.put(resolutionKey, new Id[]{ prescriberContactId, hospitalAccountId });
                }
            }

            // Fall back to Account-based resolution when no Contact match
            if (prescriberContactId == null && resolvedPhysicianId == null && String.isNotBlank(resolutionKey)) {
                if (resolvedPhysicianIdsByKey.containsKey(resolutionKey)) {
                    resolvedPhysicianId = resolvedPhysicianIdsByKey.get(resolutionKey);
                } else {
                    resolvedPhysicianId = resolvePhysician(req.physicianName, req.hospitalName);
                    if (resolvedPhysicianId == null) {
                        resolvedPhysicianId = createPlaceholderAccount(req.physicianName, req.hospitalName);
                    }
                    resolvedPhysicianIdsByKey.put(resolutionKey, resolvedPhysicianId);
                }
            }

            if (res.resolvedPhysicianName == null) {
                res.resolvedPhysicianName = accountNamesById.containsKey(resolvedPhysicianId)
                    ? accountNamesById.get(resolvedPhysicianId)
                    : req.physicianName;
            }

            res.prescriberContactId = prescriberContactId;
            res.hospitalAccountId   = hospitalAccountId;

            Visit_Report__c vr = new Visit_Report__c(
                Physician__c        = resolvedPhysicianId,
                Prescriber__c       = prescriberContactId,
                Hospital__c         = hospitalAccountId,
                Rep__c              = UserInfo.getUserId(),
                Voice_Transcript__c = req.transcript,
                Visit_Date__c       = req.visitDate != null ? req.visitDate : Date.today(),
                Visit_Outcome__c    = String.isNotBlank(req.visitOutcome) ? req.visitOutcome : 'Neutral',
                Visit_Type__c       = String.isNotBlank(req.visitType) ? req.visitType : 'In-Person Clinic',
                AI_Summary__c       = req.aiSummary,
                Engagement_Score__c = req.engagementScore
            );

            reportsToInsert.add(vr);
            validIndexes.add(i);
            results.add(res);
        }

        if (!reportsToInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(reportsToInsert, false);

            for (Integer j = 0; j < saveResults.size(); j++) {
                Database.SaveResult sr = saveResults[j];
                Result res = results[validIndexes[j]];
                if (sr.isSuccess()) {
                    res.success = true;
                    res.visitReportId = sr.getId();
                    res.visitReportName = reportsToInsert[j].Name;
                } else {
                    res.success = false;
                    res.errorMessage = sr.getErrors()[0].getMessage();
                }
            }
        }

        return results;
    }

    // ─── HELPERS ──────────────────────────────────────────────────────────────

    /**
     * Try to resolve physician to a Contact linked to a hospital Account.
     * Preferred over Account-based resolution when reps use the Contact model.
     */
    @TestVisible
    private static Contact resolveContact(String physicianName, String hospitalName) {
        if (String.isBlank(physicianName)) return null;

        String searchName    = physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim();
        String wildcardName  = '%' + searchName + '%';

        List<Contact> candidates = [
            SELECT Id, Name, AccountId, Account.Name
            FROM   Contact
            WHERE  (Name LIKE :wildcardName OR Name LIKE :('%Dr%' + searchName + '%'))
            ORDER  BY LastModifiedDate DESC
            LIMIT  5
        ];

        if (candidates.isEmpty()) return null;
        if (candidates.size() == 1) return candidates[0];

        if (String.isNotBlank(hospitalName)) {
            for (Contact con : candidates) {
                if (con.Account != null && con.Account.Name.containsIgnoreCase(hospitalName)) {
                    return con;
                }
            }
        }

        return candidates[0];
    }

    /**
     * Attempt to find an existing physician Account by name (and optionally
     * hospital/facility name for disambiguation).
     * Returns the Account Id or null if not found.
     */
    @TestVisible
    private static Id resolvePhysician(String physicianName, String hospitalName) {
        if (String.isBlank(physicianName)) return null;

        // Normalise: strip leading "Dr. " / "Dr " for broader match
        String searchName = physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim();
        String wildcardName = '%' + searchName + '%';

        List<Account> candidates = [
            SELECT Id, Name
            FROM Account
            WHERE (Name LIKE :wildcardName OR Name LIKE :('%Dr%' + searchName + '%'))
            AND RecordType.DeveloperName = 'Physician'
            ORDER BY LastModifiedDate DESC
            LIMIT 5
        ];

        if (candidates.isEmpty()) {
            // Broader search without RecordType filter
            candidates = [
                SELECT Id, Name
                FROM Account
                WHERE Name LIKE :wildcardName
                ORDER BY LastModifiedDate DESC
                LIMIT 5
            ];
        }

        if (candidates.isEmpty()) return null;
        if (candidates.size() == 1) return candidates[0].Id;

        // Disambiguate by hospital name if provided
        if (String.isNotBlank(hospitalName)) {
            String hospitalWildcard = '%' + hospitalName.trim() + '%';
            for (Account acc : candidates) {
                if (acc.Name.containsIgnoreCase(hospitalName)) {
                    return acc.Id;
                }
            }
        }

        return candidates[0].Id; // best match
    }

    private static String buildResolutionKey(String physicianName, String hospitalName) {
        if (String.isBlank(physicianName)) {
            return null;
        }

        String normalizedName = physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim().toLowerCase();
        String normalizedHospital = String.isBlank(hospitalName) ? '' : hospitalName.trim().toLowerCase();
        return normalizedName + '|' + normalizedHospital;
    }

    /**
     * Create a stub Account record for a physician not yet in the system.
     * This ensures the visit is still logged and the rep can update it later.
     */
    private static Id createPlaceholderAccount(String physicianName, String hospitalName) {
        try {
            String name = String.isNotBlank(physicianName) ? physicianName : 'Unknown Physician';
            Account acc = new Account(
                Name        = name,
                Description = 'Placeholder created by PostVisitLogAgent. '
                              + (String.isNotBlank(hospitalName) ? 'Hospital: ' + hospitalName : '')
                              + ' — Please verify and merge.'
            );
            insert acc;
            return acc.Id;
        } catch (Exception e) {
            return null;
        }
    }
}
