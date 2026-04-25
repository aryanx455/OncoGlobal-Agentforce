/**
 * ScheduleVisitAction
 * Creates a Salesforce Event on the rep's calendar for a planned physician visit.
 * Also attempts to create a Salesforce Scheduler ServiceAppointment (IAM / FSL)
 * when Scheduler is enabled in the org — silently falls back to Event-only if not.
 *
 * Conflict detection: checks the rep's existing calendar before inserting.
 * Slot defaulting: 3 working days from today at 10:00 when no preference given.
 */
public without sharing class ScheduleVisitAction {

    private static final Integer DEFAULT_DURATION_MINUTES = 30;
    private static final Integer DEFAULT_DAYS_AHEAD       = 3;

    // ─── INPUT / OUTPUT ───────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(required=true label='Physician Name'
            description='Name of physician to visit (e.g. "Dr. Gupta"). Used to find Contact record and label the calendar event.')
        public String physicianName;

        @InvocableVariable(label='Hospital / Clinic Name'
            description='Name of the facility (e.g. "Apollo Hospital"). Used as Event location.')
        public String hospitalName;

        @InvocableVariable(label='Visit Report ID'
            description='Existing Visit Report to link this appointment to when scheduling a follow-up.')
        public Id visitReportId;

        @InvocableVariable(label='Preferred Date (YYYY-MM-DD)'
            description='Requested date for the visit. Defaults to 3 working days from today if blank.')
        public String preferredDate;

        @InvocableVariable(label='Preferred Time (HH:MM 24-hour, e.g. "10:00")'
            description='Requested start time. Defaults to 10:00 if blank.')
        public String preferredTime;

        @InvocableVariable(label='Duration Minutes (default 30)')
        public Integer durationMinutes;

        @InvocableVariable(label='Notes'
            description='Objective or prep notes — product to discuss, samples to carry, key ask.')
        public String notes;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Calendar Event ID')
        public String eventId;

        @InvocableVariable(label='Service Appointment ID (IAM — if Scheduler is enabled)')
        public String serviceAppointmentId;

        @InvocableVariable(label='Scheduled Date Time (formatted)')
        public String scheduledDateTime;

        @InvocableVariable(label='Calendar Conflict Warning')
        public String conflictWarning;
    }

    // ─── INVOCABLE ────────────────────────────────────────────────────────────

    @InvocableMethod(
        label='Schedule Visit Appointment'
        description='Adds a planned physician visit to the rep calendar as a Salesforce Event. Checks for calendar conflicts and suggests the slot. Also creates a Salesforce Scheduler Service Appointment (IAM) when the org has Scheduler enabled.'
        category='OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result res = new Result();
            res.success = false;

            try {
                Id physicianContactId = resolvePhysicianContact(req.physicianName);
                Id hospitalAccountId  = resolveHospitalAccount(req.hospitalName);

                Datetime startDt = buildStartDatetime(req.preferredDate, req.preferredTime);
                Integer  durMins = (req.durationMinutes != null && req.durationMinutes > 0)
                    ? req.durationMinutes : DEFAULT_DURATION_MINUTES;
                Datetime endDt   = startDt.addMinutes(durMins);

                // Surface conflicts but do not block the insert
                res.conflictWarning = checkCalendarConflicts(startDt, endDt);

                // WhatId: prefer the visit report, then the hospital account
                Id whatId = req.visitReportId != null ? req.visitReportId : hospitalAccountId;

                Event evt = new Event(
                    Subject       = buildSubject(req.physicianName, req.hospitalName),
                    StartDateTime = startDt,
                    EndDateTime   = endDt,
                    WhoId         = physicianContactId,
                    WhatId        = whatId,
                    OwnerId       = UserInfo.getUserId(),
                    Location      = req.hospitalName,
                    Description   = buildDescription(req, physicianContactId),
                    ShowAs        = 'Busy'
                );
                insert evt;

                res.eventId          = evt.Id;
                res.scheduledDateTime = startDt.format('dd MMM yyyy, hh:mm a');
                res.success          = true;

                // Try IAM / Salesforce Scheduler — skipped silently if not configured
                try {
                    String saId = createIAMAppointment(req, startDt, endDt, physicianContactId, hospitalAccountId);
                    if (saId != null) res.serviceAppointmentId = saId;
                } catch (Exception iam) {
                    // Scheduler not provisioned in this org — Event is sufficient
                }

            } catch (Exception e) {
                res.errorMessage = e.getMessage();
            }

            results.add(res);
        }

        return results;
    }

    // ─── IAM / Salesforce Scheduler ───────────────────────────────────────────

    private static String createIAMAppointment(Request req, Datetime startDt, Datetime endDt,
            Id physicianContactId, Id hospitalAccountId) {

        // Guard: exit early if FSL/Scheduler objects are not deployed in this org
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (!gd.containsKey('serviceappointment') || !gd.containsKey('serviceresource')) return null;

        Id userId = UserInfo.getUserId();

        // Find the running user's ServiceResource record
        List<SObject> resources = Database.query(
            'SELECT Id FROM ServiceResource WHERE RelatedRecordId = :userId AND IsActive = true LIMIT 1'
        );
        if (resources.isEmpty()) return null;

        Id resourceId = resources[0].Id;

        // Find an active ServiceTerritory for this resource
        List<SObject> members = Database.query(
            'SELECT ServiceTerritoryId FROM ServiceTerritoryMember WHERE ServiceResourceId = :resourceId AND IsActive = true LIMIT 1'
        );
        if (members.isEmpty()) return null;

        Id territoryId   = (Id) members[0].get('ServiceTerritoryId');
        Long durationMs  = endDt.getTime() - startDt.getTime();
        Integer durMins  = (Integer)(durationMs / 60000);

        SObject sa = (SObject) Type.forName('ServiceAppointment').newInstance();
        sa.put('Subject',            buildSubject(req.physicianName, req.hospitalName));
        sa.put('SchedStartTime',     startDt);
        sa.put('SchedEndTime',       endDt);
        sa.put('Duration',           durMins);
        sa.put('DurationScale',      'Minutes');
        sa.put('ServiceTerritoryId', territoryId);
        sa.put('Status',             'Scheduled');
        if (physicianContactId != null) sa.put('ContactId', physicianContactId);
        if (hospitalAccountId  != null) sa.put('AccountId', hospitalAccountId);
        if (String.isNotBlank(req.notes)) sa.put('Description', req.notes);
        insert sa;
        return (String) sa.get('Id');
    }

    // ─── Date / Time resolution ───────────────────────────────────────────────

    private static Datetime buildStartDatetime(String preferredDate, String preferredTime) {
        Date d;
        if (String.isNotBlank(preferredDate)) {
            try { d = Date.valueOf(preferredDate); }
            catch (Exception e) { d = Date.today().addDays(DEFAULT_DAYS_AHEAD); }
        } else {
            d = Date.today().addDays(DEFAULT_DAYS_AHEAD);
        }

        Integer hour = 10, minute = 0;
        if (String.isNotBlank(preferredTime)) {
            try {
                List<String> parts = preferredTime.split(':');
                hour   = Integer.valueOf(parts[0]);
                minute = parts.size() > 1 ? Integer.valueOf(parts[1]) : 0;
            } catch (Exception e) { /* default 10:00 */ }
        }

        return Datetime.newInstance(d, Time.newInstance(hour, minute, 0, 0));
    }

    // ─── Conflict check ───────────────────────────────────────────────────────

    private static String checkCalendarConflicts(Datetime startDt, Datetime endDt) {
        List<Event> conflicts = [
            SELECT Subject, StartDateTime
            FROM Event
            WHERE OwnerId    = :UserInfo.getUserId()
            AND StartDateTime < :endDt
            AND EndDateTime   > :startDt
            LIMIT 3
        ];
        if (conflicts.isEmpty()) return null;
        List<String> labels = new List<String>();
        for (Event e : conflicts) {
            labels.add(e.Subject + ' (' + e.StartDateTime.format('hh:mm a') + ')');
        }
        return String.join(labels, '; ');
    }

    // ─── Record resolution ────────────────────────────────────────────────────

    private static Id resolvePhysicianContact(String physicianName) {
        if (String.isBlank(physicianName)) return null;
        String wildcard = '%' + physicianName.replaceAll('(?i)^dr\\.?\\s+', '').trim() + '%';
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Name LIKE :wildcard LIMIT 1];
        return contacts.isEmpty() ? null : contacts[0].Id;
    }

    private static Id resolveHospitalAccount(String hospitalName) {
        if (String.isBlank(hospitalName)) return null;
        String wildcard = '%' + hospitalName.trim() + '%';
        List<Account> accounts = [SELECT Id FROM Account WHERE Name LIKE :wildcard LIMIT 1];
        return accounts.isEmpty() ? null : accounts[0].Id;
    }

    // ─── String builders ──────────────────────────────────────────────────────

    private static String buildSubject(String physicianName, String hospitalName) {
        String subj = String.isNotBlank(physicianName)
            ? 'Follow-up Visit – ' + physicianName : 'Physician Visit';
        if (String.isNotBlank(hospitalName)) subj += ' @ ' + hospitalName;
        return subj.abbreviate(255);
    }

    private static String buildDescription(Request req, Id physicianContactId) {
        List<String> lines = new List<String>{'Auto-scheduled by OncoGlobal Agentforce'};
        if (String.isNotBlank(req.notes)) lines.add('Objective: ' + req.notes);
        if (physicianContactId != null) lines.add('Physician Contact: ' + physicianContactId);
        return String.join(lines, '\n');
    }
}
