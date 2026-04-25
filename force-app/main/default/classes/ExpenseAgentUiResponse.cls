@JsonAccess(serializable='always' deserializable='always')
global class ExpenseAgentUiResponse {
    @InvocableVariable global ExpenseBillResult expense_result;
    @InvocableVariable global String expense_id;
}
