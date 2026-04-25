public with sharing class KnowledgeSearchAction {

    public class Request {
        @InvocableVariable(label='Search Query' required=true)
        public String query;

        @InvocableVariable(label='Language Preference (english or hinglish)' required=false)
        public String lang;
    }

    public class Result {
        @InvocableVariable(label='Knowledge Content')
        public String content;

        @InvocableVariable(label='Category')
        public String category;

        @InvocableVariable(label='Record Label')
        public String recordLabel;

        @InvocableVariable(label='Found')
        public Boolean found;
    }

    @InvocableMethod(
        label='Search Knowledge Base'
        description='Searches the OncoGlobal knowledge base (products, hospitals, policy, visit tips, objection handling) and returns language-appropriate content.'
        category='OncoGlobal Knowledge'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(search(req));
        }
        return results;
    }

    static Result search(Request req) {
        Result res = new Result();
        res.found = false;

        if (String.isBlank(req.query)) {
            res.content = 'No query provided.';
            return res;
        }

        String q = req.query.toLowerCase().trim();
        Boolean useHinglish = 'hinglish'.equalsIgnoreCase(req.lang == null ? '' : req.lang);

        List<OncoGlobal_Knowledge__mdt> records = [
            SELECT Label, Category__c, Keywords__c, Content_English__c, Content_Hinglish__c
            FROM OncoGlobal_Knowledge__mdt
            WHERE Keywords__c != null
            ORDER BY Label
        ];

        OncoGlobal_Knowledge__mdt bestMatch = null;
        Integer bestScore = 0;

        for (OncoGlobal_Knowledge__mdt rec : records) {
            Integer score = scoreRecord(q, rec.Keywords__c);
            if (score > bestScore) {
                bestScore = score;
                bestMatch = rec;
            }
        }

        if (bestMatch != null && bestScore > 0) {
            res.found = true;
            res.category = bestMatch.Category__c;
            res.recordLabel = bestMatch.Label;
            String content = useHinglish && String.isNotBlank(bestMatch.Content_Hinglish__c)
                ? bestMatch.Content_Hinglish__c
                : bestMatch.Content_English__c;
            // Truncate to stay within agent response limits
            res.content = content != null && content.length() > 3000
                ? content.substring(0, 3000) + '\n\n[... see full details in OncoGlobal rep portal]'
                : content;
        } else {
            res.content = useHinglish
                ? 'Maafi, is topic pe abhi knowledge base mein information nahi hai. Manager se ya OncoGlobal portal se check karein.'
                : 'Sorry, I couldn\'t find relevant information for that query in the knowledge base. Please check with your manager or the OncoGlobal rep portal.';
        }

        return res;
    }

    static Integer scoreRecord(String query, String keywordsRaw) {
        if (String.isBlank(keywordsRaw)) return 0;
        Integer score = 0;
        List<String> keywords = keywordsRaw.toLowerCase().split(',');
        for (String kw : keywords) {
            String k = kw.trim();
            if (String.isBlank(k)) continue;
            if (query.contains(k)) {
                // Longer keyword match = higher confidence
                score += k.contains(' ') ? 4 : 2;
            }
        }
        return score;
    }
}
