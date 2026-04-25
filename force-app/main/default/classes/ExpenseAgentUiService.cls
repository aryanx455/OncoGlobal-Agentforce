global with sharing class ExpenseAgentUiService {
    @InvocableMethod(
        label='Create Expense From Uploaded Bill'
        description='Creates an Expense__c record from the confirmed expense bill data collected in the custom upload UI.'
        category='Agentforce'
    )
    global static List<ExpenseAgentUiResponse> createExpenseFromUploadedBill(List<ExpenseAgentUiRequest> requests) {
        List<ExpenseAgentUiResponse> responses = new List<ExpenseAgentUiResponse>();

        for (ExpenseAgentUiRequest request : requests) {
            ExpenseBillInput input = request == null ? null : request.expense_request;
            validateExpenseBillInput(input);

            ExpenseController.ExpensePayload payload = new ExpenseController.ExpensePayload();
            payload.expense_report = new ExpenseController.ExpenseReportPayload();
            payload.expense_report.employee_name = input.employeeName;
            payload.expense_report.employee_id = input.employeeId;
            payload.expense_report.doctor_name = input.doctorName;
            payload.expense_report.doctor_contact_id = input.doctorContactId;
            payload.expense_report.facility_name = input.hospitalName;
            payload.expense_report.expense_category = input.expenseCategory;
            payload.expense_report.business_purpose = input.businessPurpose;

            payload.vendor_details = new ExpenseController.VendorDetailsPayload();
            payload.vendor_details.vendor_name = input.vendorName;
            payload.vendor_details.vendor_gstin = input.vendorGstin;
            payload.vendor_details.vendor_address = input.vendorAddress;

            payload.invoice_details = new ExpenseController.InvoiceDetailsPayload();
            payload.invoice_details.invoice_number = input.invoiceNumber;
            payload.invoice_details.invoice_date = input.invoiceDate;
            payload.invoice_details.payment_method = input.paymentMethod;

            payload.amount_details = new ExpenseController.AmountDetailsPayload();
            payload.amount_details.subtotal = input.subtotal;
            payload.amount_details.tax = input.taxAmount;
            payload.amount_details.total_amount = input.totalAmount;

            payload.tax_details = new ExpenseController.TaxDetailsPayload();
            payload.tax_details.cgst = input.cgst;
            payload.tax_details.sgst = input.sgst;
            payload.tax_details.igst = input.igst;

            payload.line_items = parseLineItems(input.lineItemsJson);

            ExpenseController.ExpenseCreateResponse createResponse = ExpenseController.createExpenseRecord(
                JSON.serialize(payload),
                input.contentDocumentId
            );

            Expense__c expense = [
                SELECT Id, Name, Doctor__c, Doctor__r.Name, Vendor__c, Amount__c, Invoice_Number__c, Invoice_Date__c
                FROM Expense__c
                WHERE Id = :createResponse.expenseId
                LIMIT 1
            ];

            ExpenseBillResult result = new ExpenseBillResult();
            result.expenseId = expense.Id;
            result.expenseName = expense.Name;
            result.doctorContactId = expense.Doctor__c;
            result.doctorName = expense.Doctor__r == null ? input.doctorName : expense.Doctor__r.Name;
            result.hospitalName = input.hospitalName;
            result.vendorName = expense.Vendor__c;
            result.invoiceNumber = expense.Invoice_Number__c;
            result.invoiceDate = expense.Invoice_Date__c == null ? null : String.valueOf(expense.Invoice_Date__c);
            result.currencyCode = String.isBlank(input.currencyCode) ? UserInfo.getDefaultCurrency() : input.currencyCode;
            result.totalAmount = expense.Amount__c;
            result.lineItemCount = createResponse.lineItemCount;
            result.statusMessage = 'Expense record created after bill extraction and user confirmation.';

            ExpenseAgentUiResponse response = new ExpenseAgentUiResponse();
            response.expense_result = result;
            response.expense_id = expense.Id;
            responses.add(response);
        }

        return responses;
    }

    private static void validateExpenseBillInput(ExpenseBillInput input) {
        if (input == null) {
            throw new AuraHandledException('Expense bill input is required.');
        }
        if (input.confirmedByUser != true) {
            throw new AuraHandledException('Review and confirm the extracted expense details before creating the expense record.');
        }
        if (String.isBlank(input.contentDocumentId)) {
            throw new AuraHandledException('Upload a receipt or invoice before confirming the expense bill.');
        }
    }

    private static List<ExpenseController.ExpenseLineItemPayload> parseLineItems(String serializedLineItems) {
        if (String.isBlank(serializedLineItems)) {
            return new List<ExpenseController.ExpenseLineItemPayload>();
        }

        Object parsed = JSON.deserializeUntyped(serializedLineItems);
        if (!(parsed instanceof List<Object>)) {
            return new List<ExpenseController.ExpenseLineItemPayload>();
        }

        List<ExpenseController.ExpenseLineItemPayload> lineItems = new List<ExpenseController.ExpenseLineItemPayload>();
        for (Object rawItem : (List<Object>) parsed) {
            Map<String, Object> itemMap = (Map<String, Object>) rawItem;
            ExpenseController.ExpenseLineItemPayload payloadItem = new ExpenseController.ExpenseLineItemPayload();
            payloadItem.item_name = (String) itemMap.get('item_name');
            payloadItem.quantity = decimalValue(itemMap.get('quantity'));
            payloadItem.unit_price = decimalValue(itemMap.get('unit_price'));
            payloadItem.total_price = decimalValue(itemMap.get('total_price'));
            lineItems.add(payloadItem);
        }

        return lineItems;
    }

    private static Decimal decimalValue(Object value) {
        if (value == null) {
            return null;
        }

        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf(String.valueOf(value));
        }
        if (value instanceof Long) {
            return Decimal.valueOf(String.valueOf(value));
        }
        if (value instanceof Double) {
            return Decimal.valueOf(String.valueOf(value));
        }

        return Decimal.valueOf(String.valueOf(value));
    }
}
