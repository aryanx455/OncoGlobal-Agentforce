Savepoint sp = Database.setSavepoint();

String expenseData = JSON.serialize(new Map<String, Object>{
    'expense_report' => new Map<String, Object>{
        'expense_category' => 'Meals',
        'business_purpose' => 'Agentforce rollback test'
    },
    'vendor_details' => new Map<String, Object>{
        'vendor_name' => 'Blue Sparrow Cafe Pvt Ltd'
    },
    'invoice_details' => new Map<String, Object>{
        'invoice_number' => 'INV-ROLLBACK-TEST',
        'invoice_date' => '2026-04-18'
    },
    'amount_details' => new Map<String, Object>{
        'total_amount' => 1911.00
    },
    'tax_details' => new Map<String, Object>(),
    'line_items' => new List<Object>{
        new Map<String, Object>{
            'item_name' => 'Business Lunch Combo',
            'quantity' => 2,
            'unit_price' => 850.00
        }
    }
});

ExpenseController.ExpenseCreateResponse response = ExpenseController.createExpenseRecord(expenseData, null);
System.debug('ROLLBACK_TEST_EXPENSE_ID=' + response.expenseId);
System.debug('ROLLBACK_TEST_LINE_ITEM_COUNT=' + response.lineItemCount);

Database.rollback(sp);
