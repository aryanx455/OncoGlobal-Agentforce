/**
 * RepCalendarController
 * AuraEnabled data layer for the oncoRepCalendar LWC and scheduleVisitAction Quick Action.
 * Returns upcoming Events + past Visit_Report__c records for the running user.
 */
public with sharing class RepCalendarController {

    // ─── Calendar entry DTO ───────────────────────────────────────────────────

    public class CalendarEntry {
        @AuraEnabled public String  id;
        @AuraEnabled public String  title;
        @AuraEnabled public String  dateKey;        // YYYY-MM-DD for JS grid matching
        @AuraEnabled public String  dateLabel;      // "Mon, 21 Apr 2026"
        @AuraEnabled public String  timeLabel;      // "10:00 AM – 10:30 AM" (events only)
        @AuraEnabled public String  type;           // 'event' | 'visit'
        @AuraEnabled public String  outcome;        // Positive | Negative | Neutral | Follow-Up Required
        @AuraEnabled public String  physicianName;
        @AuraEnabled public String  hospitalName;
        @AuraEnabled public String  summary;
        @AuraEnabled public Decimal engagementScore;
        @AuraEnabled public Boolean isPast;
    }

    // ─── Queries ──────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<CalendarEntry> getCalendarData() {
        List<CalendarEntry> entries = new List<CalendarEntry>();
        DateTime now         = DateTime.now();
        DateTime futureLimit = now.addDays(60);

        // Upcoming scheduled Events
        for (Event evt : [
            SELECT Id, Subject, StartDateTime, EndDateTime, Location, Who.Name
            FROM   Event
            WHERE  OwnerId        = :UserInfo.getUserId()
            AND    StartDateTime  > :now
            AND    StartDateTime  < :futureLimit
            ORDER  BY StartDateTime ASC
            LIMIT  50
        ]) {
            CalendarEntry e = new CalendarEntry();
            e.id            = evt.Id;
            e.title         = evt.Subject;
            e.type          = 'event';
            e.dateKey       = evt.StartDateTime.formatGmt('yyyy-MM-dd');
            e.dateLabel     = evt.StartDateTime.format('EEE, dd MMM yyyy');
            e.timeLabel     = evt.StartDateTime.format('hh:mm a') + ' – ' + evt.EndDateTime.format('hh:mm a');
            e.hospitalName  = evt.Location;
            e.physicianName = evt.Who != null ? evt.Who.Name : null;
            e.isPast        = false;
            entries.add(e);
        }

        // Past visit reports (last 60 days + today)
        for (Visit_Report__c vr : [
            SELECT Id, Name, Visit_Date__c, Visit_Outcome__c, Visit_Type__c,
                   Physician__r.Name, Prescriber__r.Name, AI_Summary__c, Engagement_Score__c
            FROM   Visit_Report__c
            WHERE  OwnerId       = :UserInfo.getUserId()
            AND    Visit_Date__c >= :Date.today().addDays(-60)
            AND    Visit_Date__c <= :Date.today()
            ORDER  BY Visit_Date__c DESC
            LIMIT  100
        ]) {
            CalendarEntry e = new CalendarEntry();
            e.id              = vr.Id;
            e.title           = vr.Name;
            e.type            = 'visit';
            e.dateKey         = String.valueOf(vr.Visit_Date__c);
            e.dateLabel       = vr.Visit_Date__c.format();
            e.outcome         = vr.Visit_Outcome__c;
            e.physicianName   = vr.Prescriber__r != null  ? vr.Prescriber__r.Name
                              : vr.Physician__r  != null  ? vr.Physician__r.Name : 'Unknown';
            e.summary         = vr.AI_Summary__c;
            e.engagementScore = vr.Engagement_Score__c;
            e.isPast          = true;
            entries.add(e);
        }

        return entries;
    }

    // ─── Schedule from Contact Quick Action ───────────────────────────────────

    @AuraEnabled
    public static Map<String, String> scheduleVisitFromContact(
            String contactId,
            String physicianName,
            String hospitalName,
            String preferredDate,
            String preferredTime,
            Integer durationMinutes,
            String notes) {

        ScheduleVisitAction.Request req = new ScheduleVisitAction.Request();
        req.physicianName    = physicianName;
        req.hospitalName     = hospitalName;
        req.preferredDate    = preferredDate;
        req.preferredTime    = preferredTime;
        req.durationMinutes  = durationMinutes;
        req.notes            = notes;

        List<ScheduleVisitAction.Result> results = ScheduleVisitAction.execute(
            new List<ScheduleVisitAction.Request>{ req }
        );

        Map<String, String> outcome = new Map<String, String>();
        if (!results.isEmpty() && results[0].success) {
            outcome.put('success',          'true');
            outcome.put('eventId',          results[0].eventId);
            outcome.put('scheduledDateTime', results[0].scheduledDateTime);
            outcome.put('conflictWarning',   results[0].conflictWarning);
            outcome.put('serviceApptId',     results[0].serviceAppointmentId);
        } else {
            outcome.put('success',       'false');
            outcome.put('errorMessage',  results.isEmpty() ? 'No result' : results[0].errorMessage);
        }
        return outcome;
    }
}
