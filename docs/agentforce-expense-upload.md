# Agentforce Expense Upload Setup

## 1. Invoice Extraction Template

`SocialMediaPostsController.generateFromFile()` calls the Flex prompt template with API name `extract_data_from_invoice`.

Input:
- `ContentDocument` of type `Record`

Recommended prompt body:

```text
You are extracting finance-ready data from an uploaded expense bill.

Use this grounded record exactly as the source document:
[RecordSnapshot:ContentDocument](RecordSnapshot:ContentDocument)

Return only strict JSON with no markdown, no explanation, and no prose before or after the JSON.

Use this schema exactly:
{
  "expense_report": {
    "employee_name": null,
    "employee_id": null,
    "expense_category": null,
    "business_purpose": null
  },
  "vendor_details": {
    "vendor_name": null,
    "vendor_gstin": null,
    "vendor_address": null
  },
  "invoice_details": {
    "invoice_number": null,
    "invoice_date": null,
    "payment_method": null,
    "currency": null
  },
  "amount_details": {
    "subtotal": null,
    "tax": null,
    "total_amount": null
  },
  "tax_details": {
    "cgst": null,
    "sgst": null,
    "igst": null
  },
  "line_items": [
    {
      "item_name": null,
      "quantity": null,
      "unit_price": null,
      "total_price": null
    }
  ]
}

Rules:
- Keep ISO date format as YYYY-MM-DD.
- Use numeric values for all amounts.
- If a value is not present, use null.
- Infer `expense_category` conservatively using the closest business category.
```

## 2. Agentforce Action Definition

Configure an agent action named `Upload Expense Bills`.

Suggested action setup:
- Trigger utterances:
  - `upload expense bills`
  - `submit an expense receipt`
  - `scan this expense invoice`
- Input experience:
  - Use LWC `c:expenseUpload`
  - The LWC sends the selected file to `ExpenseController.uploadAndProcessExpenseFile()`
- Confirmation prompt:
  - `Are these details correct?`
- Post-confirmation action:
  - Creation is handled by `ExpenseAgentUiService.createExpenseFromUploadedBill`
  - If you are wiring the pieces manually, you can alternatively call invocable Apex action `Create Expense Records From Confirmed JSON`

## 3. Invocation Logic

Recommended orchestration:
1. Agent detects an upload-related expense intent.
2. Agent launches `c:expenseUpload` as the action input experience.
3. User selects the bill and clicks `Analyze Bill`.
4. `ExpenseController.uploadAndProcessExpenseFile()` inserts `ContentVersion`, receives the `ContentDocumentId`, and calls `SocialMediaPostsController.generateFromFile()`.
5. The LWC renders the structured response for user confirmation.
6. User clicks `Confirm and Create Expense`.
7. `ExpenseController.createExpenseRecord()` creates `Expense__c`, `Expense_Line_Item__c`, and links the uploaded file.

Available invocable actions:
- `ExpenseAgentExtractionAction.extractExpenseDetails`
- `ExpenseAgentCreateAction.createExpenseRecords`
- `ExpenseAgentUiService.createExpenseFromUploadedBill`

## 4. Notes

- The LWC uses the current user record as the upload anchor when no page `recordId` exists.
- No hardcoded record IDs are required.
- If you prefer a different prompt template name, set the LWC property `promptTemplateApiName`.
