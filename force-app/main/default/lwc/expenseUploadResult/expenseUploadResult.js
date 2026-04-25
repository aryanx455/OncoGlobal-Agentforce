import { LightningElement, api } from 'lwc';

export default class ExpenseUploadResult extends LightningElement {
    @api value;

    get expenseName() {
        return this.value?.expenseName || 'Expense';
    }

    get statusMessage() {
        return this.value?.statusMessage || 'The expense and its related line items were created successfully.';
    }

    get expenseId() {
        return this.value?.expenseId || '-';
    }

    get vendorName() {
        return this.value?.vendorName || '-';
    }

    get invoiceNumber() {
        return this.value?.invoiceNumber || '-';
    }

    get invoiceDate() {
        return this.value?.invoiceDate || '-';
    }

    get lineItemCount() {
        return this.value?.lineItemCount ?? 0;
    }

    get formattedAmount() {
        const amount = this.value?.totalAmount;
        if (amount === null || amount === undefined || amount === '') {
            return '-';
        }

        const currencyCode = this.value?.currencyCode || 'USD';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: currencyCode
        }).format(amount);
    }
}