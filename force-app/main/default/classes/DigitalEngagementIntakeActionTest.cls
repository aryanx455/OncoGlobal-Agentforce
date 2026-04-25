@IsTest
private class DigitalEngagementIntakeActionTest {

    @IsTest
    static void executeClassifiesTextMessage() {
        DigitalEngagementIntakeAction.Request req = new DigitalEngagementIntakeAction.Request();
        req.channel = 'WhatsApp';
        req.messageText = 'I visited Dr. Shah and discussed Keytruda follow up';

        Test.startTest();
        List<DigitalEngagementIntakeAction.Result> results =
            DigitalEngagementIntakeAction.execute(new List<DigitalEngagementIntakeAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected digital text intake to succeed.');
        System.assertEquals('post_visit_log', results[0].recommendedTopic);
        System.assertEquals(false, results[0].mediaProcessed);
    }

    @IsTest
    static void executeProcessesReceiptContentDocument() {
        ExpenseController.testExtractedInvoiceJson = '{"expense_report":{"employee_name":"Avi","doctor_name":"Dr. Media","expense_category":"Meals","business_purpose":"Doctor lunch"},"vendor_details":{"vendor_name":"Media Cafe"},"invoice_details":{"invoice_number":"MEDIA-1","invoice_date":"' + String.valueOf(Date.today()) + '"},"amount_details":{"total_amount":250},"tax_details":{},"line_items":[]}';

        ContentVersion version = new ContentVersion(
            Title = 'media receipt',
            PathOnClient = 'media-receipt.pdf',
            VersionData = Blob.valueOf('fake media receipt')
        );
        insert version;
        version = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];

        DigitalEngagementIntakeAction.Request req = new DigitalEngagementIntakeAction.Request();
        req.channel = 'WhatsApp';
        req.contentDocumentId = version.ContentDocumentId;
        req.messageText = 'receipt';

        Test.startTest();
        List<DigitalEngagementIntakeAction.Result> results =
            DigitalEngagementIntakeAction.execute(new List<DigitalEngagementIntakeAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected digital media intake to succeed.');
        System.assertEquals(true, results[0].mediaProcessed);
        System.assert(results[0].extractedExpenseJson.contains('Media Cafe'));
    }
}
