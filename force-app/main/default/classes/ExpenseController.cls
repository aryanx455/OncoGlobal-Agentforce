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
        return createExpenseRecordInternal(expenseData, contentDocumentId, true);
    }

    public static ExpenseCreateResponse createExpenseRecordForAgent(String expenseData, Id contentDocumentId) {
        return createExpenseRecordInternal(expenseData, contentDocumentId, false);
    }

    private static ExpenseCreateResponse createExpenseRecordInternal(
        String expenseData,
        Id contentDocumentId,
        Boolean useAuraException
    ) {
        if (String.isBlank(expenseData)) {
            raiseExpenseError('Expense data is required to create records.', useAuraException);
        }

        try {
            ExpensePayload payload = parseExpensePayloadInternal(expenseData, useAuraException);
            Date invoiceDate = parseInvoiceDate(payload.invoice_details.invoice_date);
            Id duplicateExpenseId = ExpenseGuardrailAction.findDuplicateExpenseId(
                payload.invoice_details.invoice_number,
                payload.vendor_details.vendor_name,
                payload.amount_details.total_amount,
                invoiceDate
            );
            if (duplicateExpenseId != null) {
                raiseExpenseError(
                    'Potential duplicate expense detected. Existing expense record: ' + String.valueOf(duplicateExpenseId),
                    useAuraException
                );
            }

            Expense__c expense = buildExpenseRecord(payload, useAuraException);
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
        } catch (ExpenseActionException exceptionToRethrow) {
            throw exceptionToRethrow;
        } catch (DmlException dmlEx) {
            raiseExpenseError('Expense creation failed. ' + dmlEx.getDmlMessage(0), useAuraException);
        } catch (Exception ex) {
            raiseExpenseError('Expense creation failed. ' + ex.getMessage(), useAuraException);
        }

        return null;
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
        return parseExpensePayloadInternal(rawPayload, true);
    }

    private static ExpensePayload parseExpensePayloadInternal(String rawPayload, Boolean useAuraException) {
        String sanitizedPayload = sanitizeJsonResponseInternal(rawPayload, useAuraException);
        try {
            ExpensePayload parsedPayload = (ExpensePayload) JSON.deserialize(sanitizedPayload, ExpensePayload.class);
            if (parsedPayload == null) {
                raiseExpenseError('Invoice extraction returned an empty JSON payload.', useAuraException);
            }

            parsedPayload.ensureCollections();
            return parsedPayload;
        } catch (JSONException jsonEx) {
            raiseExpenseError('Invoice extraction returned invalid JSON. ' + jsonEx.getMessage(), useAuraException);
        }

        return null;
    }

    @TestVisible
    private static String sanitizeJsonResponse(String rawPayload) {
        return sanitizeJsonResponseInternal(rawPayload, true);
    }

    private static String sanitizeJsonResponseInternal(String rawPayload, Boolean useAuraException) {
        if (String.isBlank(rawPayload)) {
            raiseExpenseError('Invoice extraction returned a blank response.', useAuraException);
        }

        String sanitized = rawPayload.trim();
        if (sanitized.startsWith('```')) {
            sanitized = sanitized.replaceFirst('^```(?:json)?\\s*', '');
            sanitized = sanitized.replaceFirst('\\s*```$', '');
        }

        Integer firstBrace = sanitized.indexOf('{');
        Integer lastBrace = sanitized.lastIndexOf('}');
        if (firstBrace < 0 || lastBrace <= firstBrace) {
            raiseExpenseError('Invoice extraction response did not contain strict JSON.', useAuraException);
        }

        return sanitized.substring(firstBrace, lastBrace + 1);
    }

    private static Expense__c buildExpenseRecord(ExpensePayload payload, Boolean useAuraException) {
        Expense__c expense = new Expense__c();
        expense.Category__c = payload.expense_report.expense_category;
        expense.Description__c = payload.expense_report.business_purpose;
        expense.Doctor__c = resolveDoctorContactId(
            payload.expense_report.doctor_contact_id,
            payload.expense_report.doctor_name,
            payload.expense_report.facility_name,
            useAuraException
        );
        expense.Vendor__c = payload.vendor_details.vendor_name;
        expense.Amount__c = payload.amount_details.total_amount;
        expense.Invoice_Number__c = payload.invoice_details.invoice_number;

        if (String.isNotBlank(payload.invoice_details.invoice_date)) {
            expense.Invoice_Date__c = parseInvoiceDate(payload.invoice_details.invoice_date);
        }

        return expense;
    }

    private static Id resolveDoctorContactId(
        String doctorContactId,
        String doctorName,
        String facilityName,
        Boolean useAuraException
    ) {
        return useAuraException == true
            ? ProviderResolutionService.ensureDoctorContactForExpense(doctorContactId, doctorName, facilityName)
            : ProviderResolutionService.ensureDoctorContactForExpenseForAgent(doctorContactId, doctorName, facilityName);
    }

    private static void raiseExpenseError(String message, Boolean useAuraException) {
        if (useAuraException == true) {
            throw new AuraHandledException(message);
        }
        throw new ExpenseActionException(message);
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
        @AuraEnabled public String facility_name;
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
