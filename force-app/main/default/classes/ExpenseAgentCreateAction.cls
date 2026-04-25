public with sharing class ExpenseAgentCreateAction {
    public class Request {
        @InvocableVariable(required=true)
        public String expenseJson;

        @InvocableVariable
        public Id contentDocumentId;
    }

    public class Response {
        @InvocableVariable
        public Id expenseId;

        @InvocableVariable
        public Integer lineItemCount;
    }

    @InvocableMethod(
        label='Create Expense Records From Confirmed JSON'
        description='Creates Expense__c and Expense_Line_Item__c records from the confirmed expense JSON.'
        category='Agentforce'
    )
    public static List<Response> createExpenseRecords(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            ExpenseController.ExpenseCreateResponse createResult = ExpenseController.createExpenseRecord(
                request.expenseJson,
                request.contentDocumentId
            );

            Response response = new Response();
            response.expenseId = createResult.expenseId;
            response.lineItemCount = createResult.lineItemCount;
            responses.add(response);
        }

        return responses;
    }
}
