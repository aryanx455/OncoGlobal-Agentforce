/**
 * AgentConversationController
 * Brain behind the voice LWC and WhatsApp webhook.
 * Receives a free-text transcript, detects intent, extracts entities,
 * calls the appropriate Apex action(s), and returns a Hinglish-aware response.
 */
public without sharing class AgentConversationController {

    // ─── Public DTO ───────────────────────────────────────────────────────────

    public class AgentRequest {
        @AuraEnabled public String transcript;
        @AuraEnabled public String sessionVisitReportId;
        @AuraEnabled public String sessionPhysicianName;
    }

    public class AgentResponse {
        @AuraEnabled public Boolean success        = true;
        @AuraEnabled public String  message;
        @AuraEnabled public String  intent;
        @AuraEnabled public String  visitReportId;
        @AuraEnabled public String  physicianName;
        @AuraEnabled public Boolean policyFlagged  = false;
        @AuraEnabled public Integer tasksCreated   = 0;
    }

    // ─── Entry point (LWC + WhatsApp) ────────────────────────────────────────

    @AuraEnabled
    public static AgentResponse processMessage(AgentRequest req) {
        if (req == null || String.isBlank(req.transcript)) {
            AgentResponse r = new AgentResponse();
            r.message = 'Kuch bola nahi — dobara try karein?';
            return r;
        }

        String t = req.transcript.toLowerCase();

        // Detect intent by scoring
        Map<String, Integer> scores = new Map<String, Integer>{
            'VISIT'   => scoreVisit(t),
            'EXPENSE' => scoreExpense(t),
            'FOLLOWUP'=> scoreFollowup(t),
            'INSIGHTS'=> scoreInsights(t),
            'GREETING'=> scoreGreeting(t)
        };
        String intent = topKey(scores);

        AgentResponse resp = new AgentResponse();
        resp.intent = intent;
        resp.visitReportId  = req.sessionVisitReportId;
        resp.physicianName  = req.sessionPhysicianName;

        if (intent == 'VISIT') {
            handleVisit(req, resp);
        } else if (intent == 'EXPENSE') {
            handleExpense(req, resp);
        } else if (intent == 'FOLLOWUP') {
            handleFollowup(req, resp);
        } else if (intent == 'INSIGHTS') {
            resp.message = 'Insights feature ke liye Agentforce Builder mein check karein, ya doctor ka naam bolo to visit log karte hain!';
        } else {
            // Greeting or unrecognised
            resp.message = 'Bolo! Aaj kahan gaye? Mujhe doctor ka naam aur hospital batao, baaki main kar lunga. 😊';
        }

        return resp;
    }

    // ─── Intent handlers ──────────────────────────────────────────────────────

    private static void handleVisit(AgentRequest req, AgentResponse resp) {
        String t = req.transcript;

        String doctorName  = extractDoctorName(t);
        String hospital    = extractHospitalName(t);
        String outcome     = inferOutcome(t);
        String visitType   = inferVisitType(t);
        Decimal score      = inferEngagementScore(t, outcome);
        String summary     = buildSummary(t, doctorName, hospital, outcome);

        LogVisitAction.Request visitReq = new LogVisitAction.Request();
        visitReq.transcript     = t;
        visitReq.physicianName  = doctorName;
        visitReq.hospitalName   = hospital;
        visitReq.visitOutcome   = outcome;
        visitReq.visitType      = visitType;
        visitReq.engagementScore = score;
        visitReq.aiSummary      = summary;

        List<LogVisitAction.Result> results = LogVisitAction.execute(
            new List<LogVisitAction.Request>{ visitReq }
        );

        if (!results.isEmpty() && results[0].success) {
            LogVisitAction.Result vr = results[0];
            resp.visitReportId  = vr.visitReportId;
            resp.physicianName  = String.isNotBlank(vr.resolvedPhysicianName)
                ? vr.resolvedPhysicianName : doctorName;

            // Auto-extract topics
            autoExtractTopics(vr.visitReportId, t, outcome, score, summary);

            String drName = resp.physicianName != null ? resp.physicianName : (doctorName != null ? doctorName : 'Doctor');
            String hosp   = String.isNotBlank(hospital) ? ' at ' + hospital : '';
            resp.message  = hinglishVisitConfirm(drName, hosp, vr.visitReportName, outcome, (Integer)score);
        } else {
            String errMsg = (!results.isEmpty() && results[0].errorMessage != null)
                ? results[0].errorMessage : 'unknown error';
            resp.success = false;
            resp.message = 'Kuch issue aaya visit log karte waqt — ' + errMsg
                + '. Doctor ka naam confirm karein?';
        }
    }

    private static void handleExpense(AgentRequest req, AgentResponse resp) {
        String t = req.transcript;

        Decimal amount   = extractAmount(t);
        String  category = inferExpenseCategory(t);
        String  doctor   = String.isNotBlank(req.sessionPhysicianName)
            ? req.sessionPhysicianName : extractDoctorName(t);
        String  hospital = extractHospitalName(t);
        String  notes    = buildExpenseNotes(t, doctor, hospital);

        if (amount == null || amount <= 0) {
            resp.message = 'Amount samajh nahi aaya. Bolo — "450 rupees ka lunch tha" ya "Rs. 200 ka auto tha".';
            return;
        }

        LogExpenseAction.Request expReq = new LogExpenseAction.Request();
        expReq.amount        = amount;
        expReq.category      = category;
        expReq.physicianName = doctor;
        expReq.hospitalName  = hospital;
        expReq.notes         = notes;

        List<LogExpenseAction.Result> results = LogExpenseAction.execute(
            new List<LogExpenseAction.Request>{ expReq }
        );

        if (!results.isEmpty() && results[0].success) {
            resp.policyFlagged = results[0].policyFlagged == true;
            String catLabel    = category != null ? category.toLowerCase() : 'expense';
            resp.message = 'Rs.' + amount.setScale(0) + ' ka ' + catLabel + ' expense log ho gaya. ✅';
            if (resp.policyFlagged) {
                resp.message += '\n⚠️ Note: Yeh Rs.150 se zyada hai — compliance ke liye flag ho gaya.';
            }
            resp.message += '\n\nAur kuch tha? Follow-up tasks log karne hain?';
        } else {
            String err = (!results.isEmpty() && results[0].errorMessage != null)
                ? results[0].errorMessage : 'unknown';
            resp.success = false;
            resp.message = 'Expense log nahi ho saka — ' + err + '. Dobara try karein?';
        }
    }

    private static void handleFollowup(AgentRequest req, AgentResponse resp) {
        String t      = req.transcript;
        String doctor = String.isNotBlank(req.sessionPhysicianName)
            ? req.sessionPhysicianName : extractDoctorName(t);
        String actions = extractFollowUpActions(t);

        CreateFollowUpTasksAction.Request taskReq = new CreateFollowUpTasksAction.Request();
        taskReq.followUpActions = actions;
        taskReq.physicianName   = doctor;
        taskReq.priority        = inferPriority(t);
        if (String.isNotBlank(req.sessionVisitReportId)) {
            taskReq.visitReportId = req.sessionVisitReportId;
        }

        List<CreateFollowUpTasksAction.Result> results = CreateFollowUpTasksAction.execute(
            new List<CreateFollowUpTasksAction.Request>{ taskReq }
        );

        if (!results.isEmpty() && results[0].success) {
            Integer count    = results[0].tasksCreated != null ? results[0].tasksCreated : 1;
            resp.tasksCreated = count;
            resp.message = count + ' follow-up task' + (count > 1 ? 's' : '') + ' ban gaye! ✅\n\n'
                + buildTaskList(actions)
                + '\n\nAaj ka kaam ho gaya! Aur koi doctor ke paas gaye the?';
        } else {
            String err = (!results.isEmpty() && results[0].errorMessage != null)
                ? results[0].errorMessage : 'unknown';
            resp.success = false;
            resp.message = 'Tasks create nahi ho sake — ' + err + '. Dobara batao kya karna hai?';
        }
    }

    // ─── Auto-extract topics after visit ──────────────────────────────────────

    private static void autoExtractTopics(Id visitReportId, String transcript, String outcome, Decimal score, String summary) {
        if (visitReportId == null) return;
        ExtractTopicsAction.Request req = new ExtractTopicsAction.Request();
        req.visitReportId   = visitReportId;
        req.discussionTopics = extractTopicsFromTranscript(transcript);
        req.nextBestAction   = inferNextBestAction(transcript, outcome);
        req.engagementScore  = score;
        req.aiSummary        = summary;
        req.needsReview      = false;
        try {
            ExtractTopicsAction.execute(new List<ExtractTopicsAction.Request>{ req });
        } catch (Exception e) {
            // Non-fatal — visit is already saved
        }
    }

    // ─── Intent scoring ───────────────────────────────────────────────────────

    static Integer scoreVisit(String t) {
        Integer s = 0;
        List<String> kw = new List<String>{
            'gaya tha','gaya','visit','mila','dr.','doctor','physician',
            'hospital','clinic','met','visited','round','chamber','opd','appointment',
            'ke paas','ke pass','se mila','milne gaya','keytruda','tagrisso',
            'opdivo','herceptin','discuss','baat ki','positive raha','negative gaya'
        };
        for (String k : kw) { if (t.contains(k)) s += k.contains(' ') ? 3 : 2; }
        return s;
    }

    static Integer scoreExpense(String t) {
        Integer s = 0;
        List<String> kw = new List<String>{
            'rupees','rs.','rs ','₹','bill','expense','kharcha','lunch','dinner',
            'khana','cab','auto','train','hotel','stay','conference','ruka','gaye',
            'ticket','petrol','fuel','coffee','chai'
        };
        for (String k : kw) { if (t.contains(k)) s += k.contains(' ') ? 3 : 2; }
        return s;
    }

    static Integer scoreFollowup(String t) {
        Integer s = 0;
        List<String> kw = new List<String>{
            'bhejna','bhejunga','send','arrange','schedule','follow up','follow-up',
            'task','karna hai','call karna','milna hai','literature','cme','samples',
            'remind','next week','agle hafte','kal tak','share karna'
        };
        for (String k : kw) { if (t.contains(k)) s += k.contains(' ') ? 3 : 2; }
        return s;
    }

    static Integer scoreInsights(String t) {
        Integer s = 0;
        List<String> kw = new List<String>{
            'history','past visit','kitne visit','pehle kab','score','relationship',
            'how many','previous','last time','kitni baar'
        };
        for (String k : kw) { if (t.contains(k)) s += 3; }
        return s;
    }

    static Integer scoreGreeting(String t) {
        Integer s = 0;
        List<String> kw = new List<String>{'hi','hello','hey','namaste','kya hal','help','kya kar'};
        for (String k : kw) { if (t.contains(k)) s += 2; }
        return s;
    }

    static String topKey(Map<String, Integer> scores) {
        String best = 'GREETING';
        Integer max = 0;
        for (String k : scores.keySet()) {
            if (scores.get(k) > max) { max = scores.get(k); best = k; }
        }
        return max == 0 ? 'GREETING' : best;
    }

    // ─── Entity extraction ────────────────────────────────────────────────────

    @TestVisible
    static String extractDoctorName(String t) {
        // Regex: "Dr." or "Dr " followed by capitalized words
        Pattern p = Pattern.compile('(?i)(?:dr\\.?\\s+)([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?)');
        Matcher m = p.matcher(t);
        if (m.find()) return 'Dr. ' + m.group(1).trim();

        // "Sharma sir/madam/ji" pattern
        Pattern p2 = Pattern.compile('([A-Z][a-z]{3,})\\s+(?:sir|madam|ji|sahab)');
        Matcher m2 = p2.matcher(t);
        if (m2.find()) return 'Dr. ' + m2.group(1).trim();

        return null;
    }

    @TestVisible
    static String extractHospitalName(String t) {
        List<String> hospitals = new List<String>{
            'Apollo','Fortis','Tata Memorial','TMH','HCG','Manipal','AIIMS',
            'Narayana','Medanta','Max','RGCI','Kidwai','KEM','Aster','Columbia Asia',
            'Care Hospital','Wockhardt','Kokilaben','Breach Candy','Lilavati',
            'Hinduja','Jaslok','PD Hinduja','Global Hospital','SRCC'
        };
        for (String h : hospitals) {
            if (t.toLowerCase().contains(h.toLowerCase())) return h;
        }
        // Regex: "at/mein/ke " followed by capital Hospital/Centre/Clinic
        Pattern p = Pattern.compile('(?i)(?:at|mein|ke |@)\\s+([A-Z][\\w\\s]{2,25}(?:Hospital|Centre|Center|Clinic|Cancer|Health))');
        Matcher m = p.matcher(t);
        if (m.find()) return m.group(1).trim();
        return null;
    }

    @TestVisible
    static Decimal extractAmount(String t) {
        // "450 rupees" / "Rs. 450" / "₹450" / "450 ka bill"
        Pattern p = Pattern.compile('(?:rs\\.?\\s*|₹|inr\\s*)?([0-9]+(?:[,\\.][0-9]{2,3})?)\\s*(?:rupees?|rs\\.?|₹|ka\\s+bill|ka\\s+kharcha|kharcha|bill)?');
        Matcher m = p.matcher(t);
        Decimal best = null;
        while (m.find()) {
            String num = m.group(1).replace(',','');
            try {
                Decimal d = Decimal.valueOf(num);
                if (d > 0 && d < 500000 && (best == null || d > best)) best = d;
            } catch (Exception e) {}
        }
        return best;
    }

    static String inferOutcome(String t) {
        if (t.contains('positive') || t.contains('accha gaya') || t.contains('bahut accha')
            || t.contains('interested') || t.contains('enthusiastic') || t.contains('zaroor')
            || t.contains('bilkul') || t.contains('haan') || t.contains('agree')) return 'Positive';
        if (t.contains('negative') || t.contains('nahi mila') || t.contains('refuse')
            || t.contains('nahi maane') || t.contains('busy tha') || t.contains('gate pe rok')
            || t.contains('door se bhaga')) return 'Negative';
        if (t.contains('follow') || t.contains('dobara jaana') || t.contains('kal')
            || t.contains('next week') || t.contains('agle hafte') || t.contains('pending')) return 'Follow-Up Required';
        return 'Neutral';
    }

    static String inferVisitType(String t) {
        if (t.contains('virtual') || t.contains('zoom') || t.contains('teams')
            || t.contains('video call') || t.contains('online')) return 'Virtual Call';
        if (t.contains('conference') || t.contains('cme') || t.contains('event')
            || t.contains('seminar') || t.contains('congress')) return 'Conference / Event';
        if (t.contains('hospital round') || t.contains('ward round')
            || t.contains('rounds mein')) return 'Hospital Round';
        if (t.contains('drop in') || t.contains('drop-in')
            || t.contains('bina appointment')) return 'Drop-In';
        return 'In-Person Clinic';
    }

    static Decimal inferEngagementScore(String t, String outcome) {
        if (outcome == 'Positive') {
            if (t.contains('bahut') || t.contains('enthusiastic') || t.contains('zaroor')
                || t.contains('prescribe karunga') || t.contains('committed')) return 90;
            return 72;
        }
        if (outcome == 'Follow-Up Required') return 52;
        if (outcome == 'Negative') return 22;
        return 48;
    }

    static String inferExpenseCategory(String t) {
        if (t.contains('lunch') || t.contains('dinner') || t.contains('khana')
            || t.contains('meal') || t.contains('restaurant') || t.contains('chai')
            || t.contains('coffee') || t.contains('snack')) return 'Meal';
        if (t.contains('cab') || t.contains('auto') || t.contains('ola') || t.contains('uber')
            || t.contains('train') || t.contains('flight') || t.contains('petrol')
            || t.contains('fuel') || t.contains('bus') || t.contains('travel')) return 'Travel';
        if (t.contains('hotel') || t.contains('stay') || t.contains('ruka')
            || t.contains('accommodation')) return 'Accommodation';
        if (t.contains('sample') || t.contains('samples')) return 'Samples';
        if (t.contains('cme') || t.contains('conference') || t.contains('event')
            || t.contains('seminar')) return 'CME / Event';
        return 'Other';
    }

    static String inferPriority(String t) {
        if (t.contains('urgent') || t.contains('jaldi') || t.contains('asap')
            || t.contains('kal tak') || t.contains('aaj hi')) return 'High';
        if (t.contains('low') || t.contains('baad mein') || t.contains('koi baat nahi')) return 'Low';
        return 'Normal';
    }

    static String extractFollowUpActions(String t) {
        // Split on common conjunctions to extract multiple actions
        List<String> raw = t.split('(?i)(?:aur|and|,|;|\\.|toh|phir|plus|bhi)');
        List<String> actions = new List<String>();
        List<String> actionKw = new List<String>{
            'bhejna','send','arrange','call','schedule','share',
            'remind','book','confirm','submit','drop','visit'
        };
        for (String chunk : raw) {
            String c = chunk.trim();
            if (String.isBlank(c) || c.length() < 4) continue;
            for (String kw : actionKw) {
                if (c.toLowerCase().contains(kw)) {
                    actions.add(c.replaceAll('(?i)(bhejna hai|karna hai|chahiye|please|zara)', '').trim());
                    break;
                }
            }
        }
        if (actions.isEmpty()) {
            // Fallback: use full transcript as one action
            actions.add(t.length() > 120 ? t.substring(0, 120) : t);
        }
        return String.join(actions, ', ');
    }

    static String extractTopicsFromTranscript(String t) {
        List<String> drugs = new List<String>{
            'Keytruda','Tagrisso','Herceptin','Opdivo','Iressa','Avastin',
            'Ibrance','Imfinzi','Lynparza','Tarceva','Zytiga','Xtandi','Calquence'
        };
        List<String> topics = new List<String>();
        for (String drug : drugs) {
            if (t.toLowerCase().contains(drug.toLowerCase())) topics.add(drug);
        }
        List<String> clinicalKw = new List<String>{
            'PD-L1','EGFR','ALK','HER2','BRCA','TMB','MSI-H',
            'formulary','CME','trial','enrollment','first-line','second-line',
            'dosing','side effect','response','progression','combination'
        };
        for (String kw : clinicalKw) {
            if (t.toLowerCase().contains(kw.toLowerCase())) topics.add(kw);
        }
        return topics.isEmpty() ? 'General oncology discussion' : String.join(topics, '; ');
    }

    static String inferNextBestAction(String t, String outcome) {
        if (outcome == 'Positive') return 'Send clinical data and schedule follow-up in 2 weeks';
        if (outcome == 'Follow-Up Required') return 'Follow up next week to get final decision';
        if (outcome == 'Negative') return 'Plan re-engagement strategy with manager';
        return 'Send product information and check back in 3 weeks';
    }

    static String buildSummary(String t, String doctor, String hospital, String outcome) {
        String dr   = doctor   != null ? doctor   : 'physician';
        String hosp = hospital != null ? hospital : 'the facility';
        return 'Visit at ' + hosp + ' with ' + dr + '. Outcome: ' + outcome + '. '
            + (t.length() > 80 ? t.substring(0, 80) + '...' : t);
    }

    static String buildExpenseNotes(String t, String doctor, String hospital) {
        List<String> parts = new List<String>();
        if (doctor   != null) parts.add('With ' + doctor);
        if (hospital != null) parts.add('at ' + hospital);
        return parts.isEmpty() ? t.substring(0, Math.min(100, t.length())) : String.join(parts, ' ');
    }

    static String buildTaskList(String actions) {
        List<String> items = actions.split(',');
        List<String> numbered = new List<String>();
        for (Integer i = 0; i < items.size(); i++) {
            numbered.add((i + 1) + '. ' + items[i].trim());
        }
        return String.join(numbered, '\n');
    }

    // ─── Response builders ────────────────────────────────────────────────────

    static String hinglishVisitConfirm(String doctor, String hospital, String reportName, String outcome, Integer score) {
        String outcomeEmoji = outcome == 'Positive' ? '😊✅' : outcome == 'Negative' ? '😔' : '🔄';
        String reportStr    = String.isNotBlank(reportName) ? ' Report: ' + reportName + '.' : '';
        return 'Ho gaya! ' + doctor + ' ki visit log kar di' + hospital + '. '
            + outcomeEmoji + ' Outcome: ' + outcome + '. Score: ' + score + '/100.' + reportStr
            + '\n\nKoi expense tha? Ya follow-up tasks create karne hain?';
    }
}
