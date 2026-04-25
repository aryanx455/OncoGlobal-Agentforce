@JsonAccess(serializable='always' deserializable='always')
global class ExpenseBillResult {
    @AuraEnabled @InvocableVariable global String expenseId;
    @AuraEnabled @InvocableVariable global String expenseName;
    @AuraEnabled @InvocableVariable global String doctorContactId;
    @AuraEnabled @InvocableVariable global String doctorName;
    @AuraEnabled @InvocableVariable global String hospitalName;
    @AuraEnabled @InvocableVariable global String vendorName;
    @AuraEnabled @InvocableVariable global String invoiceNumber;
    @AuraEnabled @InvocableVariable global String invoiceDate;
    @AuraEnabled @InvocableVariable global String currencyCode;
    @AuraEnabled @InvocableVariable global Decimal totalAmount;
    @AuraEnabled @InvocableVariable global Integer lineItemCount;
    @AuraEnabled @InvocableVariable global String statusMessage;
}
