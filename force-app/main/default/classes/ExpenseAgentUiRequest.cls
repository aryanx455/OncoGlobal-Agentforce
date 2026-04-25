@JsonAccess(serializable='always' deserializable='always')
global class ExpenseAgentUiRequest {
    @InvocableVariable(required=true)
    global ExpenseBillInput expense_request;
}
