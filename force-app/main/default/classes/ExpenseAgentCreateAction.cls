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

        @InvocableVariable
        public String errorMessage;
    }

    @InvocableMethod(
        label='Create Expense Records From Confirmed JSON'
        description='Creates Expense__c and Expense_Line_Item__c records from the confirmed expense JSON.'
        category='Agentforce'
    )
    public static List<Response> createExpenseRecords(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            Response response = new Response();
            try {
                ExpenseController.ExpenseCreateResponse createResult = ExpenseController.createExpenseRecordForAgent(
                    request.expenseJson,
                    request.contentDocumentId
                );
                response.expenseId = createResult.expenseId;
                response.lineItemCount = createResult.lineItemCount;
            } catch (Exception ex) {
                response.errorMessage = ex.getMessage();
            }
            responses.add(response);
        }

        return responses;
    }
}
