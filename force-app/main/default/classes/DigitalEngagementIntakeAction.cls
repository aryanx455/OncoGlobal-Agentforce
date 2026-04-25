/**
 * Normalizes WhatsApp/SMS style intake for Agentforce.
 *
 * This action does not depend on a specific vendor webhook. If Digital
 * Engagement passes a ContentDocumentId for media, the action can reuse the
 * existing expense extraction pipeline. Otherwise it classifies the message and
 * routes the agent toward the right topic.
 */
public with sharing class DigitalEngagementIntakeAction {

    public class Request {
        @InvocableVariable(label='Channel')
        public String channel;

        @InvocableVariable(label='Sender Name')
        public String senderName;

        @InvocableVariable(label='Sender Address')
        public String senderAddress;

        @InvocableVariable(label='Message Text')
        public String messageText;

        @InvocableVariable(label='Media Content Document ID')
        public Id contentDocumentId;

        @InvocableVariable(label='Doctor or Provider Name')
        public String providerName;

        @InvocableVariable(label='Facility Name')
        public String facilityName;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Detected Intent')
        public String detectedIntent;

        @InvocableVariable(label='Recommended Topic')
        public String recommendedTopic;

        @InvocableVariable(label='Media Processed')
        public Boolean mediaProcessed;

        @InvocableVariable(label='Extracted Expense JSON')
        public String extractedExpenseJson;

        @InvocableVariable(label='Standard Object Usage')
        public String standardObjectUsage;

        @InvocableVariable(label='Response Guidance')
        public String responseGuidance;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Process Digital Engagement Intake'
        description='Classifies WhatsApp/SMS style messages and processes ContentDocument receipt media when available.'
        category='OncoGlobal Digital Engagement'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(process(req));
        }
        return results;
    }

    private static Result process(Request req) {
        Result res = new Result();
        res.success = false;

        try {
            String text = req == null ? '' : String.valueOf(req.messageText).toLowerCase();
            Boolean hasMedia = req != null && req.contentDocumentId != null;

            if (hasMedia || containsAny(text, new List<String>{ 'receipt', 'invoice', 'bill', 'expense' })) {
                res.detectedIntent = 'Expense Receipt Intake';
                res.recommendedTopic = 'expense_bill_upload';
            } else if (containsAny(text, new List<String>{ 'brief', 'history', 'last visit', 'relationship' })) {
                res.detectedIntent = 'Provider Brief';
                res.recommendedTopic = 'provider_brief';
            } else if (containsAny(text, new List<String>{ 'met ', 'meeting', 'visited', 'visit', 'discussed' })) {
                res.detectedIntent = 'Post Visit Log';
                res.recommendedTopic = 'post_visit_log';
            } else {
                res.detectedIntent = 'General Field Message';
                res.recommendedTopic = 'knowledge_search';
            }

            if (hasMedia) {
                ExpenseController.ExpenseProcessingResponse extracted =
                    ExpenseController.processExpenseFile(req.contentDocumentId, null);
                res.mediaProcessed = true;
                res.extractedExpenseJson = extracted == null ? null : extracted.rawJson;
                res.responseGuidance = 'Receipt media was processed from Salesforce Files. Ask the rep to review and confirm before creating the expense.';
            } else {
                res.mediaProcessed = false;
                res.responseGuidance = 'Route this message to ' + res.recommendedTopic + ' and continue the standard agent flow.';
            }

            res.standardObjectUsage = buildStandardObjectUsage();
            res.success = true;
        } catch (Exception e) {
            res.errorMessage = e.getMessage();
        }

        return res;
    }

    private static Boolean containsAny(String text, List<String> needles) {
        if (String.isBlank(text)) {
            return false;
        }
        for (String needle : needles) {
            if (text.contains(needle)) {
                return true;
            }
        }
        return false;
    }

    private static String buildStandardObjectUsage() {
        List<String> objects = new List<String>{ 'MessagingEndUser', 'MessagingSession', 'ContentDocument', 'ContentVersion' };
        return 'Designed for standard Digital Engagement/File objects: ' + String.join(objects, ', ') + '.';
    }
}
