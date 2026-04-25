@IsTest
private class ExpenseControllerTest {
    @IsTest
    static void createExpenseRecordCreatesExpenseAndLineItems() {
        ContentVersion version = new ContentVersion(
            Title = 'Taxi Receipt',
            PathOnClient = 'taxi-receipt.pdf',
            VersionData = Blob.valueOf('sample expense bill')
        );
        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];

        String doctorName = 'Dr. Neha Rao Expense Test ' + String.valueOf(Crypto.getRandomInteger());

        String payload = '{"expense_report":{"employee_name":"Avi Agarwal","employee_id":"E-1001","doctor_name":"' + doctorName + '","expense_category":"Travel","business_purpose":"Airport transfer"},"vendor_details":{"vendor_name":"ABC Travels Pvt Ltd","vendor_gstin":"09ABCDE1234F1Z5","vendor_address":"New Delhi, India"},"invoice_details":{"invoice_number":"INV-2026-001","invoice_date":"2026-04-10","payment_method":"Credit Card","currency":"INR"},"amount_details":{"subtotal":450.00,"tax":50.00,"total_amount":500.00},"tax_details":{"cgst":25.00,"sgst":25.00,"igst":0.00},"line_items":[{"item_name":"Cab Ride","quantity":1,"unit_price":450.00,"total_price":450.00}]}';

        Test.startTest();
        ExpenseController.ExpenseCreateResponse response = ExpenseController.createExpenseRecord(
            payload,
            version.ContentDocumentId
        );
        Test.stopTest();

        System.assertNotEquals(null, response.expenseId);
        System.assertEquals(1, response.lineItemCount);

        Expense__c expense = [
            SELECT Category__c, Description__c, Doctor__c, Doctor__r.Name, Doctor__r.AccountId, Vendor__c, Amount__c, Invoice_Number__c, Invoice_Date__c
            FROM Expense__c
            WHERE Id = :response.expenseId
        ];
        System.assertEquals('Travel', expense.Category__c);
        System.assertEquals('Airport transfer', expense.Description__c);
        System.assertNotEquals(null, expense.Doctor__c);
        System.assertEquals(doctorName, expense.Doctor__r.Name);
        System.assertNotEquals(null, expense.Doctor__r.AccountId);
        System.assertEquals('ABC Travels Pvt Ltd', expense.Vendor__c);
        System.assertEquals(500, expense.Amount__c);
        System.assertEquals('INV-2026-001', expense.Invoice_Number__c);
        System.assertEquals(Date.newInstance(2026, 4, 10), expense.Invoice_Date__c);

        List<Expense_Line_Item__c> lineItems = [
            SELECT Name, Quantity__c, Unit_Price__c, Total_Price__c
            FROM Expense_Line_Item__c
            WHERE Expense__c = :expense.Id
        ];
        System.assertEquals(1, lineItems.size());
        System.assertEquals('Cab Ride', lineItems[0].Name);
        System.assertEquals(1, lineItems[0].Quantity__c);
        System.assertEquals(450, lineItems[0].Unit_Price__c);
        System.assertEquals(450, lineItems[0].Total_Price__c);

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
            AND LinkedEntityId = :expense.Id
        ];
        System.assertEquals(1, links.size());
    }

    @IsTest
    static void parseExpensePayloadStripsMarkdownFence() {
        String wrappedJson = '```json\n{"expense_report":{"expense_category":"Travel","business_purpose":"Client visit"},"vendor_details":{"vendor_name":"ABC Travels Pvt Ltd"},"invoice_details":{"invoice_number":"INV-100","invoice_date":"2026-04-10"},"amount_details":{"total_amount":500},"tax_details":{"cgst":0,"sgst":0,"igst":0},"line_items":[]}\n```';

        ExpenseController.ExpensePayload payload = ExpenseController.parseExpensePayload(wrappedJson);

        System.assertEquals('Travel', payload.expense_report.expense_category);
        System.assertEquals('ABC Travels Pvt Ltd', payload.vendor_details.vendor_name);
        System.assertEquals(0, payload.line_items.size());
    }

    @IsTest
    static void uploadAndProcessExpenseFileCreatesContentDocumentAndParsesExtraction() {
        ExpenseController.testExtractedInvoiceJson = '{"expense_report":{"employee_name":"Avi Agarwal","employee_id":"E-1001","doctor_name":"Dr. Meera Shah","expense_category":"Meals","business_purpose":"Doctor meeting lunch"},"vendor_details":{"vendor_name":"Cafe Care","vendor_gstin":"09ABCDE1234F1Z5","vendor_address":"Mumbai, India"},"invoice_details":{"invoice_number":"MEAL-101","invoice_date":"2026-04-12","payment_method":"UPI","currency":"INR"},"amount_details":{"subtotal":900.00,"tax":90.00,"total_amount":990.00},"tax_details":{"cgst":45.00,"sgst":45.00,"igst":0.00},"line_items":[{"item_name":"Lunch","quantity":1,"unit_price":900.00,"total_price":900.00}]}';

        Test.startTest();
        ExpenseController.ExpenseProcessingResponse response = ExpenseController.uploadAndProcessExpenseFile(
            'meal-receipt.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('fake pdf body')),
            'application/pdf',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, response.contentDocumentId);
        System.assertEquals('Cafe Care', response.payload.vendor_details.vendor_name);
        System.assertEquals('Dr. Meera Shah', response.payload.expense_report.doctor_name);
        System.assertEquals('MEAL-101', response.payload.invoice_details.invoice_number);
        System.assertEquals(990, response.payload.amount_details.total_amount);
    }

    @IsTest
    static void createExpenseRecordBlocksDuplicateInvoice() {
        Expense__c existing = new Expense__c(
            Vendor__c = 'Duplicate Cafe',
            Amount__c = 250,
            Invoice_Number__c = 'DUP-101',
            Invoice_Date__c = Date.today()
        );
        insert existing;

        String payload = '{"expense_report":{"expense_category":"Meals","business_purpose":"Doctor meeting"},"vendor_details":{"vendor_name":"Duplicate Cafe"},"invoice_details":{"invoice_number":"DUP-101","invoice_date":"' + String.valueOf(Date.today()) + '"},"amount_details":{"total_amount":250},"tax_details":{},"line_items":[]}';

        Test.startTest();
        try {
            ExpenseController.createExpenseRecord(payload, null);
            System.assert(false, 'Expected duplicate creation to be blocked.');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex, 'Expected duplicate exception.');
        }
        Test.stopTest();
    }
}
