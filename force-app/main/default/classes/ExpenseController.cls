public with sharing class ExpenseController {
    private static final String DEFAULT_PROMPT_TEMPLATE_API_NAME = 'Expense_Bill_Extraction';
    private static final String CONTENT_DOCUMENT_INPUT_NAME = 'Input:ContentDocument';
    @TestVisible private static String testExtractedInvoiceJson;

    @AuraEnabled
    public static ExpenseProcessingResponse uploadAndProcessExpenseFile(
        String fileName,
        String base64Data,
        String contentType,
        Id parentRecordId
    ) {
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('A file name is required to upload the expense bill.');
        }
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('File data is required to upload the expense bill.');
        }

        try {
            ContentVersion version = new ContentVersion(
                Title = deriveTitleFromFileName(fileName),
                PathOnClient = fileName,
                VersionData = EncodingUtil.base64Decode(normalizeBase64Data(base64Data))
            );

            if (parentRecordId != null) {
                version.FirstPublishLocationId = parentRecordId;
            }

            insert version;

            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
                LIMIT 1
            ];

            return processExpenseFile(version.ContentDocumentId, null);
        } catch (AuraHandledException exceptionToRethrow) {
            throw exceptionToRethrow;
        } catch (Exception ex) {
            throw new AuraHandledException('Expense file upload failed. ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static ExpenseProcessingResponse processExpenseFile(Id contentDocumentId, String promptTemplateApiName) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('A ContentDocumentId is required to extract expense details.');
        }

        validateContentDocument(contentDocumentId);

        String templateApiName = String.isBlank(promptTemplateApiName)
            ? DEFAULT_PROMPT_TEMPLATE_API_NAME
            : promptTemplateApiName.trim();

        try {
            String rawJson = sanitizeJsonResponse(extractInvoiceJson(contentDocumentId));
            ExpensePayload payload = parseExpensePayload(rawJson);

            ExpenseProcessingResponse response = new ExpenseProcessingResponse();
            response.contentDocumentId = contentDocumentId;
            response.promptTemplateApiName = templateApiName;
            response.rawJson = rawJson;
            response.payload = payload;
            return response;
        } catch (AuraHandledException exceptionToRethrow) {
            throw exceptionToRethrow;
        } catch (Exception ex) {
            throw new AuraHandledException('Invoice extraction failed. ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static ExpenseCreateResponse createExpenseRecord(String expenseData, Id contentDocumentId) {
        if (String.isBlank(expenseData)) {
            throw new AuraHandledException('Expense data is required to create records.');
        }

        try {
            ExpensePayload payload = parseExpensePayload(expenseData);
            Date invoiceDate = parseInvoiceDate(payload.invoice_details.invoice_date);
            Id duplicateExpenseId = ExpenseGuardrailAction.findDuplicateExpenseId(
                payload.invoice_details.invoice_number,
                payload.vendor_details.vendor_name,
                payload.amount_details.total_amount,
                invoiceDate
            );
            if (duplicateExpenseId != null) {
                throw new AuraHandledException(
                    'Potential duplicate expense detected. Existing expense record: ' + String.valueOf(duplicateExpenseId)
                );
            }

            Expense__c expense = buildExpenseRecord(payload);
            insert expense;

            List<Expense_Line_Item__c> lineItems = buildLineItems(payload, expense.Id);
            if (!lineItems.isEmpty()) {
                insert lineItems;
            }

            if (contentDocumentId != null) {
                linkDocumentToExpense(contentDocumentId, expense.Id);
            }

            ExpenseCreateResponse response = new ExpenseCreateResponse();
            response.expenseId = expense.Id;
            response.lineItemCount = lineItems.size();
            response.contentDocumentId = contentDocumentId;
            return response;
        } catch (AuraHandledException exceptionToRethrow) {
            throw exceptionToRethrow;
        } catch (DmlException dmlEx) {
            throw new AuraHandledException('Expense creation failed. ' + dmlEx.getDmlMessage(0));
        } catch (Exception ex) {
            throw new AuraHandledException('Expense creation failed. ' + ex.getMessage());
        }
    }

    @TestVisible
    private static ConnectApi.EinsteinPromptTemplateGenerationsInput buildPromptRequest(Id contentDocumentId) {
        ConnectApi.WrappedValue inputValue = new ConnectApi.WrappedValue();
        inputValue.value = new Map<String, Object>{
            'id' => contentDocumentId,
            'type' => 'ContentDocument'
        };

        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>{
            CONTENT_DOCUMENT_INPUT_NAME => inputValue
        };

        ConnectApi.EinsteinPromptTemplateGenerationsInput request = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        request.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        request.additionalConfig.applicationName = 'AgentforceExpenseUpload';
        request.isPreview = false;
        request.inputParams = inputParams;
        return request;
    }

    @TestVisible
    private static String extractInvoiceJson(Id contentDocumentId) {
        if (Test.isRunningTest() && testExtractedInvoiceJson != null) {
            return testExtractedInvoiceJson;
        }

        return SocialMediaPostsController.generateFromFile(String.valueOf(contentDocumentId));
    }

    @TestVisible
    private static ExpensePayload parseExpensePayload(String rawPayload) {
        String sanitizedPayload = sanitizeJsonResponse(rawPayload);
        try {
            ExpensePayload parsedPayload = (ExpensePayload) JSON.deserialize(sanitizedPayload, ExpensePayload.class);
            if (parsedPayload == null) {
                throw new AuraHandledException('Invoice extraction returned an empty JSON payload.');
            }

            parsedPayload.ensureCollections();
            return parsedPayload;
        } catch (JSONException jsonEx) {
            throw new AuraHandledException('Invoice extraction returned invalid JSON. ' + jsonEx.getMessage());
        }
    }

    @TestVisible
    private static String sanitizeJsonResponse(String rawPayload) {
        if (String.isBlank(rawPayload)) {
            throw new AuraHandledException('Invoice extraction returned a blank response.');
        }

        String sanitized = rawPayload.trim();
        if (sanitized.startsWith('```')) {
            sanitized = sanitized.replaceFirst('^```(?:json)?\\s*', '');
            sanitized = sanitized.replaceFirst('\\s*```$', '');
        }

        Integer firstBrace = sanitized.indexOf('{');
        Integer lastBrace = sanitized.lastIndexOf('}');
        if (firstBrace < 0 || lastBrace <= firstBrace) {
            throw new AuraHandledException('Invoice extraction response did not contain strict JSON.');
        }

        return sanitized.substring(firstBrace, lastBrace + 1);
    }

    private static Expense__c buildExpenseRecord(ExpensePayload payload) {
        Expense__c expense = new Expense__c();
        expense.Category__c = payload.expense_report.expense_category;
        expense.Description__c = payload.expense_report.business_purpose;
        expense.Doctor__c = resolveDoctorContactId(
            payload.expense_report.doctor_contact_id,
            payload.expense_report.doctor_name
        );
        expense.Vendor__c = payload.vendor_details.vendor_name;
        expense.Amount__c = payload.amount_details.total_amount;
        expense.Invoice_Number__c = payload.invoice_details.invoice_number;

        if (String.isNotBlank(payload.invoice_details.invoice_date)) {
            expense.Invoice_Date__c = parseInvoiceDate(payload.invoice_details.invoice_date);
        }

        return expense;
    }

    private static Id resolveDoctorContactId(String doctorContactId, String doctorName) {
        if (String.isNotBlank(doctorContactId)) {
            return (Id) doctorContactId;
        }

        String normalizedName = String.isBlank(doctorName) ? null : doctorName.trim();
        if (String.isBlank(normalizedName)) {
            return null;
        }

        List<Contact> exactMatches = [
            SELECT Id
            FROM Contact
            WHERE Name = :normalizedName
            LIMIT 1
        ];
        if (!exactMatches.isEmpty()) {
            return exactMatches[0].Id;
        }

        Contact doctor = buildDoctorContact(normalizedName);
        insert doctor;
        return doctor.Id;
    }

    private static Contact buildDoctorContact(String doctorName) {
        Contact doctor = new Contact();
        doctor.AccountId = resolveDoctorAccountId(doctorName);
        List<String> nameParts = doctorName.split('\\s+');
        if (nameParts.size() > 1) {
            doctor.LastName = nameParts.remove(nameParts.size() - 1);
            doctor.FirstName = String.join(nameParts, ' ');
        } else {
            doctor.LastName = doctorName;
        }
        return doctor;
    }

    private static Id resolveDoctorAccountId(String doctorName) {
        if (String.isBlank(doctorName)) {
            return null;
        }

        List<Account> exactMatches = [
            SELECT Id
            FROM Account
            WHERE Name = :doctorName
            LIMIT 1
        ];
        if (!exactMatches.isEmpty()) {
            return exactMatches[0].Id;
        }

        Account physicianAccount = new Account(Name = doctorName);
        Id physicianRecordTypeId = getPhysicianRecordTypeId();
        if (physicianRecordTypeId != null) {
            physicianAccount.RecordTypeId = physicianRecordTypeId;
        }
        insert physicianAccount;
        return physicianAccount.Id;
    }

    private static Id getPhysicianRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Physician');
        return recordTypeInfo == null ? null : recordTypeInfo.getRecordTypeId();
    }

    private static List<Expense_Line_Item__c> buildLineItems(ExpensePayload payload, Id expenseId) {
        List<Expense_Line_Item__c> lineItems = new List<Expense_Line_Item__c>();
        for (ExpenseLineItemPayload item : payload.line_items) {
            if (item == null || String.isBlank(item.item_name)) {
                continue;
            }

            lineItems.add(new Expense_Line_Item__c(
                Expense__c = expenseId,
                Name = item.item_name,
                Quantity__c = item.quantity,
                Unit_Price__c = item.unit_price
            ));
        }

        return lineItems;
    }

    private static void linkDocumentToExpense(Id contentDocumentId, Id expenseId) {
        List<ContentDocumentLink> existingLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :expenseId
            LIMIT 1
        ];

        if (!existingLinks.isEmpty()) {
            return;
        }

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = expenseId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    private static void validateContentDocument(Id contentDocumentId) {
        List<ContentDocument> matches = [
            SELECT Id
            FROM ContentDocument
            WHERE Id = :contentDocumentId
            LIMIT 1
        ];

        if (matches.isEmpty()) {
            throw new AuraHandledException('The uploaded file could not be found in Salesforce Files.');
        }
    }

    private static String normalizeBase64Data(String base64Data) {
        String normalized = base64Data.trim();
        Integer dataUrlMarkerIndex = normalized.indexOf('base64,');
        if (dataUrlMarkerIndex >= 0) {
            normalized = normalized.substring(dataUrlMarkerIndex + 7);
        }
        return normalized;
    }

    private static String deriveTitleFromFileName(String fileName) {
        String title = fileName == null ? 'Expense Bill' : fileName.trim();
        Integer extensionIndex = title.lastIndexOf('.');
        if (extensionIndex > 0) {
            title = title.substring(0, extensionIndex);
        }
        return String.isBlank(title) ? 'Expense Bill' : title;
    }

    private static Date parseInvoiceDate(String invoiceDate) {
        if (String.isBlank(invoiceDate)) {
            return null;
        }
        return Date.valueOf(invoiceDate);
    }

    public class ExpenseProcessingResponse {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String promptTemplateApiName;
        @AuraEnabled public String rawJson;
        @AuraEnabled public ExpensePayload payload;
    }

    public class ExpenseCreateResponse {
        @AuraEnabled public Id expenseId;
        @AuraEnabled public Integer lineItemCount;
        @AuraEnabled public Id contentDocumentId;
    }

    public class ExpensePayload {
        @AuraEnabled public ExpenseReportPayload expense_report;
        @AuraEnabled public VendorDetailsPayload vendor_details;
        @AuraEnabled public InvoiceDetailsPayload invoice_details;
        @AuraEnabled public AmountDetailsPayload amount_details;
        @AuraEnabled public TaxDetailsPayload tax_details;
        @AuraEnabled public List<ExpenseLineItemPayload> line_items;

        public void ensureCollections() {
            expense_report = expense_report == null ? new ExpenseReportPayload() : expense_report;
            vendor_details = vendor_details == null ? new VendorDetailsPayload() : vendor_details;
            invoice_details = invoice_details == null ? new InvoiceDetailsPayload() : invoice_details;
            amount_details = amount_details == null ? new AmountDetailsPayload() : amount_details;
            tax_details = tax_details == null ? new TaxDetailsPayload() : tax_details;
            line_items = line_items == null ? new List<ExpenseLineItemPayload>() : line_items;
        }
    }

    public class ExpenseReportPayload {
        @AuraEnabled public String employee_name;
        @AuraEnabled public String employee_id;
        @AuraEnabled public String doctor_name;
        @AuraEnabled public String doctor_contact_id;
        @AuraEnabled public String expense_category;
        @AuraEnabled public String business_purpose;
    }

    public class VendorDetailsPayload {
        @AuraEnabled public String vendor_name;
        @AuraEnabled public String vendor_gstin;
        @AuraEnabled public String vendor_address;
    }

    public class InvoiceDetailsPayload {
        @AuraEnabled public String invoice_number;
        @AuraEnabled public String invoice_date;
        @AuraEnabled public String payment_method;
    }

    public class AmountDetailsPayload {
        @AuraEnabled public Decimal subtotal;
        @AuraEnabled public Decimal tax;
        @AuraEnabled public Decimal total_amount;
    }

    public class TaxDetailsPayload {
        @AuraEnabled public Decimal cgst;
        @AuraEnabled public Decimal sgst;
        @AuraEnabled public Decimal igst;
    }

    public class ExpenseLineItemPayload {
        @AuraEnabled public String item_name;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unit_price;
        @AuraEnabled public Decimal total_price;
    }
}
