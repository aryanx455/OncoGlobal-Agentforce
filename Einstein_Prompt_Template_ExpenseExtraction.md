# Einstein Prompt Template Setup for Expense Extraction

## Template Name
`ExpenseExtraction`

## Input Variables
- **Name**: `Input:ContentDocument`
- **Type**: Record (ContentDocument)
- **Description**: The uploaded expense bill/receipt/invoice file

## Prompt Template
```
Extract structured data from this expense bill/receipt/invoice. Return ONLY valid JSON in this exact format:

{
  "expense_report": {
    "doctor_name": "Doctor or physician name if the bill is associated with a doctor; otherwise null",
    "expense_category": "Travel|Meals|Office Supplies|Other",
    "business_purpose": "Brief description of expense purpose"
  },
  "vendor_details": {
    "vendor_name": "Vendor name",
    "vendor_gstin": "GSTIN if present",
    "vendor_address": "Vendor address"
  },
  "invoice_details": {
    "invoice_number": "Invoice number",
    "invoice_date": "YYYY-MM-DD",
    "payment_method": "Payment method"
  },
  "amount_details": {
    "subtotal": 0.00,
    "tax": 0.00,
    "total_amount": 0.00
  },
  "tax_details": {
    "cgst": 0.00,
    "sgst": 0.00,
    "igst": 0.00
  },
  "line_items": [
    {
      "item_name": "Item description",
      "quantity": 1,
      "unit_price": 0.00,
      "total_price": 0.00
    }
  ]
}

Use [RecordSnapshot:ContentDocument] to analyze the document content. Ensure all numeric values are decimals and dates are in YYYY-MM-DD format.
```

## Setup Steps
1. Navigate to Einstein Prompt Builder in Salesforce
2. Create new Prompt Template
3. Configure input variable as Record type for ContentDocument
4. Paste the prompt template above
5. Test with sample ContentDocument
6. Publish the template

## Integration
Update `ExpenseController.processExpenseFile()` to use the actual template name instead of placeholder.
