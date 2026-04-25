@IsTest
private class ExpenseAgentUiServiceTest {
    @IsTest
    static void missingInputReturnsAgentforceSafeMessage() {
        ExpenseAgentUiRequest request = new ExpenseAgentUiRequest();

        Test.startTest();
        List<ExpenseAgentUiResponse> responses = ExpenseAgentUiService.createExpenseFromUploadedBill(
            new List<ExpenseAgentUiRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(null, responses[0].expense_id);
        System.assertNotEquals(null, responses[0].expense_result);
        System.assert(
            responses[0].expense_result.statusMessage.contains('Expense bill input is required'),
            responses[0].expense_result.statusMessage
        );
    }

    @IsTest
    static void unconfirmedUploadReturnsAgentforceSafeMessage() {
        ExpenseAgentUiRequest request = new ExpenseAgentUiRequest();
        request.expense_request = new ExpenseBillInput();
        request.expense_request.confirmedByUser = false;

        Test.startTest();
        List<ExpenseAgentUiResponse> responses = ExpenseAgentUiService.createExpenseFromUploadedBill(
            new List<ExpenseAgentUiRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(null, responses[0].expense_id);
        System.assertNotEquals(null, responses[0].expense_result);
        System.assert(
            responses[0].expense_result.statusMessage.contains('Review and confirm'),
            responses[0].expense_result.statusMessage
        );
    }

    @IsTest
    static void duplicateExpenseReturnsAgentforceSafeMessage() {
        ContentVersion version = new ContentVersion(
            Title = 'Duplicate Agentforce Bill',
            PathOnClient = 'duplicate-agentforce-bill.pdf',
            VersionData = Blob.valueOf('duplicate expense bill')
        );
        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        Expense__c existing = new Expense__c(
            Vendor__c = 'Duplicate Agentforce Vendor',
            Amount__c = 375,
            Invoice_Number__c = 'AGENT-DUP-001',
            Invoice_Date__c = Date.today()
        );
        insert existing;

        ExpenseBillInput input = new ExpenseBillInput();
        input.confirmedByUser = true;
        input.contentDocumentId = String.valueOf(version.ContentDocumentId);
        input.expenseCategory = 'Travel';
        input.businessPurpose = 'Doctor visit travel';
        input.vendorName = 'Duplicate Agentforce Vendor';
        input.invoiceNumber = 'AGENT-DUP-001';
        input.invoiceDate = String.valueOf(Date.today());
        input.totalAmount = 375;

        ExpenseAgentUiRequest request = new ExpenseAgentUiRequest();
        request.expense_request = input;

        Test.startTest();
        List<ExpenseAgentUiResponse> responses = ExpenseAgentUiService.createExpenseFromUploadedBill(
            new List<ExpenseAgentUiRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(null, responses[0].expense_id);
        System.assertNotEquals(null, responses[0].expense_result);
        System.assert(
            responses[0].expense_result.statusMessage.contains('duplicate expense'),
            responses[0].expense_result.statusMessage
        );
    }

    @IsTest
    static void malformedLineItemsJsonDoesNotBlockExpenseCreation() {
        ContentVersion version = new ContentVersion(
            Title = 'Malformed Line Items Agentforce Bill',
            PathOnClient = 'malformed-line-items-agentforce-bill.pdf',
            VersionData = Blob.valueOf('expense bill with malformed line items')
        );
        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        ExpenseBillInput input = new ExpenseBillInput();
        input.confirmedByUser = true;
        input.contentDocumentId = String.valueOf(version.ContentDocumentId);
        input.expenseCategory = 'Travel';
        input.businessPurpose = 'Doctor visit travel';
        input.vendorName = 'Malformed Line Item Vendor';
        input.invoiceNumber = 'AGENT-LINEITEM-001';
        input.invoiceDate = String.valueOf(Date.today());
        input.totalAmount = 882;
        input.lineItemsJson = '[{"item_name":"Cab ride","quantity":1,"unit_price":640,"total_price":640}';

        ExpenseAgentUiRequest request = new ExpenseAgentUiRequest();
        request.expense_request = input;

        Test.startTest();
        List<ExpenseAgentUiResponse> responses = ExpenseAgentUiService.createExpenseFromUploadedBill(
            new List<ExpenseAgentUiRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertNotEquals(null, responses[0].expense_id);
        System.assertNotEquals(null, responses[0].expense_result);
        System.assertEquals(0, responses[0].expense_result.lineItemCount);
        System.assert(
            responses[0].expense_result.statusMessage.contains('Expense record created'),
            responses[0].expense_result.statusMessage
        );
    }
}
