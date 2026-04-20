/**
 * WhatsAppWebhookController
 * Public REST endpoint that receives Twilio WhatsApp webhooks and routes them
 * through AgentConversationController. Returns TwiML XML response.
 *
 * Setup:
 * 1. Create a Force.com Site (Setup → Sites) and set this class as accessible.
 * 2. Point your Twilio WhatsApp Sandbox webhook to:
 *    https://<your-site-domain>/services/apexrest/whatsapp/webhook
 * 3. Map WhatsApp phone numbers to Salesforce users via User.MobilePhone or
 *    the WhatsApp_Session__c lookup below.
 */
@RestResource(urlMapping='/whatsapp/webhook/*')
global without sharing class WhatsAppWebhookController {

    // ── Session store (in-memory per transaction; cross-message state via query) ──

    global class WhatsAppSession {
        public String fromNumber;
        public String visitReportId;
        public String physicianName;
    }

    // ── HTTP POST handler ──────────────────────────────────────────────────────

    @HttpPost
    global static void handleIncomingMessage() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            // Parse Twilio form-encoded body
            Map<String, String> params = parseFormBody(req.requestBody.toString());

            String fromNumber = params.get('From');    // e.g. whatsapp:+919876543210
            String body       = params.get('Body');    // The text message
            String numMedia   = params.get('NumMedia');// Number of media attachments
            String mediaUrl   = params.get('MediaUrl0');

            if (String.isBlank(body) && String.isNotBlank(numMedia) && Integer.valueOf(numMedia) > 0) {
                // Voice note or image sent — acknowledge gracefully
                body = '[Media received — please send as text for now]';
            }

            if (String.isBlank(body)) {
                sendTwiML(res, 'Main kuch samajh nahi saka. Apna visit text mein bhejo jaise: "Dr. Sharma ke paas gaya Apollo mein, positive raha".');
                return;
            }

            // Load session state from a recent visit report (today's, this user)
            WhatsAppSession session = loadSession(fromNumber);

            // Build request for AgentConversationController
            AgentConversationController.AgentRequest agentReq = new AgentConversationController.AgentRequest();
            agentReq.transcript            = body;
            agentReq.sessionVisitReportId  = session.visitReportId;
            agentReq.sessionPhysicianName  = session.physicianName;

            // Process
            AgentConversationController.AgentResponse agentResp =
                AgentConversationController.processMessage(agentReq);

            // Persist session state updates
            if (String.isNotBlank(agentResp.visitReportId)) {
                saveSession(fromNumber, agentResp.visitReportId, agentResp.physicianName);
            }

            // Reply via TwiML
            sendTwiML(res, agentResp.message);

        } catch (Exception e) {
            System.debug('WhatsApp webhook error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            sendTwiML(res, 'System mein kuch issue aaya. Dobara try karein ya app open karein.');
        }
    }

    // ── Session management via Visit_Report__c ────────────────────────────────

    private static WhatsAppSession loadSession(String fromNumber) {
        WhatsAppSession s = new WhatsAppSession();
        s.fromNumber = fromNumber;

        // Look for a visit report created today by a user whose mobile matches this number
        String cleanNumber = fromNumber != null
            ? fromNumber.replace('whatsapp:', '').replace('+91', '').trim()
            : '';

        if (String.isNotBlank(cleanNumber)) {
            List<User> users = [
                SELECT Id FROM User
                WHERE MobilePhone LIKE :('%' + cleanNumber)
                AND IsActive = true
                LIMIT 1
            ];

            if (!users.isEmpty()) {
                List<Visit_Report__c> todayVRs = [
                    SELECT Id, Physician__r.Name, Prescriber__r.Name
                    FROM   Visit_Report__c
                    WHERE  OwnerId = :users[0].Id
                    AND    Visit_Date__c = :Date.today()
                    ORDER  BY CreatedDate DESC
                    LIMIT  1
                ];
                if (!todayVRs.isEmpty()) {
                    s.visitReportId = todayVRs[0].Id;
                    s.physicianName = todayVRs[0].Prescriber__r != null
                        ? todayVRs[0].Prescriber__r.Name
                        : todayVRs[0].Physician__r?.Name;
                }
            }
        }

        return s;
    }

    private static void saveSession(String fromNumber, String visitReportId, String physicianName) {
        // Session is implicitly persisted via the Visit_Report__c record.
        // Future messages will find today's report in loadSession().
        // No additional table needed for hackathon.
    }

    // ── TwiML helpers ─────────────────────────────────────────────────────────

    private static void sendTwiML(RestResponse res, String message) {
        // WhatsApp messages from Twilio support plain text — no rich formatting
        String safeMsg = message != null
            ? message.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            : '';

        // Remove emoji for cleaner WhatsApp delivery (optional — comment out to keep)
        // safeMsg = safeMsg.replaceAll('[^\\x00-\\x7F]', '');

        res.addHeader('Content-Type', 'application/xml; charset=UTF-8');
        res.responseBody = Blob.valueOf(
            '<?xml version="1.0" encoding="UTF-8"?>'
            + '<Response>'
            + '<Message>' + safeMsg + '</Message>'
            + '</Response>'
        );
        res.statusCode = 200;
    }

    // ── Form body parser ───────────────────────────────────────────────────────

    private static Map<String, String> parseFormBody(String body) {
        Map<String, String> params = new Map<String, String>();
        if (String.isBlank(body)) return params;
        for (String pair : body.split('&')) {
            List<String> kv = pair.split('=', 2);
            if (kv.size() == 2) {
                params.put(urlDecode(kv[0]), urlDecode(kv[1]));
            } else if (kv.size() == 1) {
                params.put(urlDecode(kv[0]), '');
            }
        }
        return params;
    }

    private static String urlDecode(String s) {
        if (String.isBlank(s)) return '';
        return EncodingUtil.urlDecode(s.replace('+', ' '), 'UTF-8');
    }
}
