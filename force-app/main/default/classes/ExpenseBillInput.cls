@JsonAccess(serializable='always' deserializable='always')
global class ExpenseBillInput {
    @AuraEnabled @InvocableVariable global String contentDocumentId;
    @AuraEnabled @InvocableVariable global String rawJson;
    @AuraEnabled @InvocableVariable global String employeeName;
    @AuraEnabled @InvocableVariable global String employeeId;
    @AuraEnabled @InvocableVariable global String doctorName;
    @AuraEnabled @InvocableVariable global String doctorContactId;
    @AuraEnabled @InvocableVariable global String hospitalName;
    @AuraEnabled @InvocableVariable global String expenseCategory;
    @AuraEnabled @InvocableVariable global String businessPurpose;
    @AuraEnabled @InvocableVariable global String vendorName;
    @AuraEnabled @InvocableVariable global String vendorGstin;
    @AuraEnabled @InvocableVariable global String vendorAddress;
    @AuraEnabled @InvocableVariable global String invoiceNumber;
    @AuraEnabled @InvocableVariable global String invoiceDate;
    @AuraEnabled @InvocableVariable global String paymentMethod;
    @AuraEnabled @InvocableVariable global String currencyCode;
    @AuraEnabled @InvocableVariable global Decimal subtotal;
    @AuraEnabled @InvocableVariable global Decimal taxAmount;
    @AuraEnabled @InvocableVariable global Decimal totalAmount;
    @AuraEnabled @InvocableVariable global Decimal cgst;
    @AuraEnabled @InvocableVariable global Decimal sgst;
    @AuraEnabled @InvocableVariable global Decimal igst;
    @AuraEnabled @InvocableVariable global Boolean confirmedByUser;
    @AuraEnabled @InvocableVariable global String lineItemsJson;
}
