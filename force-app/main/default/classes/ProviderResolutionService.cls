public with sharing class ProviderResolutionService {
    public class Resolution {
        public Boolean success = false;
        public Boolean needsClarification = false;
        public String errorMessage;
        public String clarificationMessage;
        public Id physicianAccountId;
        public Id doctorContactId;
        public Id facilityAccountId;
        public String physicianName;
        public String contactName;
        public String facilityName;
        public Integer doctorMatchCount = 0;
        public Integer facilityMatchCount = 0;
        public Boolean createdPhysicianAccount = false;
    }

    private class DoctorCandidate {
        Id physicianAccountId;
        Id doctorContactId;
        Id facilityAccountId;
        String physicianName;
        String contactName;
        String facilityName;
        String source;
    }

    public static Resolution resolveDoctor(
        String doctorName,
        String facilityName,
        Boolean createPhysicianAccountFromContact,
        Boolean requireDoctor
    ) {
        Resolution result = new Resolution();
        String cleanDoctor = cleanDoctorName(doctorName);

        if (String.isBlank(cleanDoctor)) {
            if (requireDoctor == true) {
                return clarification(result, 'Please provide the doctor name so I can link this to the right provider.');
            }
            result.success = true;
            return result;
        }

        List<Account> facilities = findFacilities(facilityName);
        result.facilityMatchCount = facilities.size();
        if (String.isNotBlank(facilityName) && facilities.size() > 1) {
            List<Account> exactFacilities = filterExactFacilities(facilities, facilityName);
            if (exactFacilities.size() == 1) {
                facilities = exactFacilities;
            } else if (exactFacilities.size() > 1) {
                return clarification(
                    result,
                    'I found multiple hospitals named "' + facilityName.trim() + '". Please confirm a unique detail like city, branch, or account name. Options: ' + formatFacilities(exactFacilities)
                );
            }
        }

        List<DoctorCandidate> candidates = findDoctorCandidates(cleanDoctor);
        result.doctorMatchCount = candidates.size();

        if (String.isNotBlank(facilityName) && !facilities.isEmpty()) {
            candidates = filterByFacility(candidates, facilities, facilityName);
        } else if (String.isNotBlank(facilityName)) {
            candidates = filterByFacilityText(candidates, facilityName);
        }

        candidates = preferExactDoctorMatches(candidates, cleanDoctor);
        candidates = dedupeCandidates(candidates);

        if (candidates.isEmpty()) {
            return clarification(
                result,
                'I could not find a doctor matching "' + doctorName.trim() + '"' +
                (String.isBlank(facilityName) ? '.' : ' at "' + facilityName.trim() + '".') +
                ' Please confirm the doctor name or hospital.'
            );
        }

        if (candidates.size() > 1) {
            return clarification(
                result,
                'I found multiple doctors matching "' + doctorName.trim() + '". Please confirm the hospital/clinic. Options: ' + formatCandidates(candidates)
            );
        }

        DoctorCandidate selected = candidates[0];
        result.success = true;
        result.physicianAccountId = selected.physicianAccountId;
        result.doctorContactId = selected.doctorContactId;
        result.facilityAccountId = selected.facilityAccountId;
        result.physicianName = selected.physicianName;
        result.contactName = selected.contactName;
        result.facilityName = selected.facilityName;

        if (result.physicianAccountId == null && result.doctorContactId != null && createPhysicianAccountFromContact == true) {
            Account physicianAccount = createPhysicianAccountForContact(selected);
            result.physicianAccountId = physicianAccount.Id;
            result.physicianName = physicianAccount.Name;
            result.createdPhysicianAccount = true;
        }

        return result;
    }

    public static Id ensureDoctorContactForExpense(String doctorContactId, String doctorName, String facilityName) {
        if (String.isNotBlank(doctorContactId)) {
            try {
                Id contactId = (Id) doctorContactId;
                List<Contact> contacts = [SELECT Id FROM Contact WHERE Id = :contactId LIMIT 1];
                if (!contacts.isEmpty()) {
                    return contactId;
                }
            } catch (Exception ex) {
                throw new AuraHandledException('The selected doctor contact is not a valid Salesforce Contact.');
            }
        }

        if (String.isBlank(doctorName)) {
            return null;
        }

        Resolution resolution = resolveDoctor(doctorName, facilityName, true, true);
        if (resolution.needsClarification == true || resolution.success != true) {
            throw new AuraHandledException(resolution.clarificationMessage);
        }
        if (resolution.doctorContactId != null) {
            return resolution.doctorContactId;
        }

        Contact contact = buildContactForResolvedAccount(resolution.physicianAccountId, resolution.physicianName);
        insert contact;
        return contact.Id;
    }

    private static Resolution clarification(Resolution result, String message) {
        result.success = false;
        result.needsClarification = true;
        result.errorMessage = message;
        result.clarificationMessage = message;
        return result;
    }

    private static List<Account> findFacilities(String facilityName) {
        if (String.isBlank(facilityName)) {
            return new List<Account>();
        }

        String cleanFacility = facilityName.trim();
        String wildcard = '%' + cleanFacility + '%';
        return [
            SELECT Id, Name, BillingCity, RecordType.DeveloperName
            FROM Account
            WHERE Name LIKE :wildcard
            ORDER BY LastModifiedDate DESC
            LIMIT 20
        ];
    }

    private static List<Account> filterExactFacilities(List<Account> facilities, String facilityName) {
        List<Account> exact = new List<Account>();
        String cleanFacility = normalize(facilityName);
        for (Account facility : facilities) {
            if (normalize(facility.Name) == cleanFacility) {
                exact.add(facility);
            }
        }
        return exact;
    }

    private static List<DoctorCandidate> findDoctorCandidates(String cleanDoctor) {
        String wildcard = '%' + cleanDoctor + '%';
        String drWildcard = '%Dr%' + cleanDoctor + '%';
        List<DoctorCandidate> candidates = new List<DoctorCandidate>();

        for (Contact contactRecord : [
            SELECT Id, Name, AccountId, Account.Name, Account.ParentId, Account.Parent.Name,
                   Account.RecordType.DeveloperName
            FROM Contact
            WHERE Name LIKE :wildcard OR Name LIKE :drWildcard
            ORDER BY LastModifiedDate DESC
            LIMIT 20
        ]) {
            DoctorCandidate candidate = new DoctorCandidate();
            candidate.doctorContactId = contactRecord.Id;
            candidate.contactName = contactRecord.Name;
            candidate.physicianName = contactRecord.Name;
            if (contactRecord.Account != null && !isLikelyFacilityAccount(contactRecord.Account)) {
                candidate.physicianAccountId = contactRecord.AccountId;
                candidate.facilityAccountId = contactRecord.Account.ParentId;
                candidate.facilityName = contactRecord.Account.Parent == null ? null : contactRecord.Account.Parent.Name;
            } else {
                candidate.facilityAccountId = contactRecord.AccountId;
                candidate.facilityName = contactRecord.Account == null ? null : contactRecord.Account.Name;
            }
            candidate.source = 'Contact';
            candidates.add(candidate);
        }

        for (Account accountRecord : [
            SELECT Id, Name, ParentId, Parent.Name, RecordType.DeveloperName
            FROM Account
            WHERE Name LIKE :wildcard OR Name LIKE :drWildcard
            ORDER BY LastModifiedDate DESC
            LIMIT 20
        ]) {
            if (isLikelyFacilityAccount(accountRecord)) {
                continue;
            }
            DoctorCandidate candidate = new DoctorCandidate();
            candidate.physicianAccountId = accountRecord.Id;
            candidate.physicianName = accountRecord.Name;
            candidate.facilityAccountId = accountRecord.ParentId;
            candidate.facilityName = accountRecord.Parent == null ? null : accountRecord.Parent.Name;
            candidate.source = 'Account';
            candidates.add(candidate);
        }

        return candidates;
    }

    private static Boolean isLikelyFacilityAccount(Account accountRecord) {
        String recordTypeName = accountRecord.RecordType == null ? null : accountRecord.RecordType.DeveloperName;
        if (recordTypeName == 'Physician' || recordTypeName == 'Healthcare_Professional' || recordTypeName == 'PersonAccount') {
            return false;
        }
        if (recordTypeName == 'Healthcare_Facility') {
            return true;
        }
        String cleanName = normalize(accountRecord.Name);
        return cleanName.contains('facility') || cleanName.contains('hospital') || cleanName.contains('clinic');
    }

    private static List<DoctorCandidate> filterByFacility(
        List<DoctorCandidate> candidates,
        List<Account> facilities,
        String facilityName
    ) {
        Set<Id> facilityIds = new Set<Id>();
        for (Account facility : facilities) {
            facilityIds.add(facility.Id);
        }

        List<DoctorCandidate> filtered = new List<DoctorCandidate>();
        for (DoctorCandidate candidate : candidates) {
            if ((candidate.facilityAccountId != null && facilityIds.contains(candidate.facilityAccountId))
                || containsNormalized(candidate.facilityName, facilityName)) {
                filtered.add(candidate);
            }
        }
        return filtered;
    }

    private static List<DoctorCandidate> filterByFacilityText(List<DoctorCandidate> candidates, String facilityName) {
        List<DoctorCandidate> filtered = new List<DoctorCandidate>();
        for (DoctorCandidate candidate : candidates) {
            if (containsNormalized(candidate.facilityName, facilityName)) {
                filtered.add(candidate);
            }
        }
        return filtered;
    }

    private static List<DoctorCandidate> preferExactDoctorMatches(List<DoctorCandidate> candidates, String cleanDoctor) {
        List<DoctorCandidate> exact = new List<DoctorCandidate>();
        for (DoctorCandidate candidate : candidates) {
            String candidateName = String.isNotBlank(candidate.contactName) ? candidate.contactName : candidate.physicianName;
            if (normalize(cleanDoctorName(candidateName)) == normalize(cleanDoctor)) {
                exact.add(candidate);
            }
        }
        return exact.isEmpty() ? candidates : exact;
    }

    private static List<DoctorCandidate> dedupeCandidates(List<DoctorCandidate> candidates) {
        List<DoctorCandidate> deduped = new List<DoctorCandidate>();
        Set<String> keys = new Set<String>();
        for (DoctorCandidate candidate : candidates) {
            String key = String.valueOf(candidate.doctorContactId) + '|' + String.valueOf(candidate.physicianAccountId) + '|' + String.valueOf(candidate.facilityAccountId);
            if (!keys.contains(key)) {
                keys.add(key);
                deduped.add(candidate);
            }
        }
        return deduped;
    }

    private static Account createPhysicianAccountForContact(DoctorCandidate selected) {
        String accountName = String.isNotBlank(selected.contactName) ? selected.contactName : selected.physicianName;
        List<Account> existing = [
            SELECT Id, Name
            FROM Account
            WHERE Name = :accountName
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        Account physician = new Account(Name = accountName);
        Id physicianRecordTypeId = getPhysicianRecordTypeId();
        if (physicianRecordTypeId != null) {
            physician.RecordTypeId = physicianRecordTypeId;
        }
        if (selected.facilityAccountId != null && Schema.SObjectType.Account.fields.getMap().containsKey('ParentId')) {
            physician.ParentId = selected.facilityAccountId;
        }
        insert physician;
        return physician;
    }

    private static Contact buildContactForResolvedAccount(Id accountId, String doctorName) {
        Contact contactRecord = new Contact();
        contactRecord.AccountId = accountId;

        List<String> parts = String.isBlank(doctorName)
            ? new List<String>{ 'Doctor' }
            : doctorName.trim().split('\\s+');
        if (parts.size() > 1) {
            contactRecord.LastName = parts.remove(parts.size() - 1);
            contactRecord.FirstName = String.join(parts, ' ');
        } else {
            contactRecord.LastName = parts[0];
        }
        return contactRecord;
    }

    private static Id getPhysicianRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Physician');
        return info == null ? null : info.getRecordTypeId();
    }

    private static String formatCandidates(List<DoctorCandidate> candidates) {
        List<String> labels = new List<String>();
        Integer limitCount = Math.min(5, candidates.size());
        for (Integer i = 0; i < limitCount; i++) {
            DoctorCandidate candidate = candidates[i];
            String name = String.isNotBlank(candidate.contactName) ? candidate.contactName : candidate.physicianName;
            labels.add(name + (String.isBlank(candidate.facilityName) ? '' : ' at ' + candidate.facilityName));
        }
        return String.join(labels, '; ');
    }

    private static String formatFacilities(List<Account> facilities) {
        List<String> labels = new List<String>();
        Integer limitCount = Math.min(5, facilities.size());
        for (Integer i = 0; i < limitCount; i++) {
            labels.add(facilities[i].Name + (String.isBlank(facilities[i].BillingCity) ? '' : ' (' + facilities[i].BillingCity + ')'));
        }
        return String.join(labels, '; ');
    }

    private static Boolean containsNormalized(String source, String value) {
        return String.isNotBlank(source)
            && String.isNotBlank(value)
            && normalize(source).contains(normalize(value));
    }

    public static String cleanDoctorName(String rawName) {
        if (String.isBlank(rawName)) {
            return null;
        }
        String cleaned = rawName.trim();
        cleaned = cleaned.replaceAll('(?i)^doctor\\s+', '');
        cleaned = cleaned.replaceAll('(?i)^dr\\.?\\s+', '');
        return cleaned.trim();
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }
}
