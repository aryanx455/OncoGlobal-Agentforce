public with sharing class ExpenseAgentExtractionAction {
    public class Request {
        @InvocableVariable(required=true)
        public Id contentDocumentId;

        @InvocableVariable
        public String promptTemplateApiName;
    }

    public class Response {
        @InvocableVariable
        public Id contentDocumentId;

        @InvocableVariable
        public String rawJson;
    }

    @InvocableMethod(
        label='Extract Expense Details From Bill'
        description='Runs a Prompt Builder template against an uploaded ContentDocument and returns strict JSON.'
        category='Agentforce'
    )
    public static List<Response> extractExpenseDetails(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            ExpenseController.ExpenseProcessingResponse extraction = ExpenseController.processExpenseFile(
                request.contentDocumentId,
                request.promptTemplateApiName
            );

            Response response = new Response();
            response.contentDocumentId = extraction.contentDocumentId;
            response.rawJson = extraction.rawJson;
            responses.add(response);
        }

        return responses;
    }
}
