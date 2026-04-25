import { LightningElement, api } from 'lwc';

export default class ExpenseUploadResult extends LightningElement {
    @api value;

    get isCreated() {
        return Boolean(this.value?.expenseId);
    }

    get shellClass() {
        return `result-shell ${this.isCreated ? 'result-shell--success' : 'result-shell--warning'}`;
    }

    get eyebrowText() {
        return this.isCreated ? 'Expense Created' : 'Expense Not Created';
    }

    get expenseName() {
        if (this.isCreated) {
            return this.value?.expenseName || 'Expense';
        }
        return this.value?.expenseName || 'Needs review';
    }

    get statusMessage() {
        if (this.value?.statusMessage) {
            return this.value.statusMessage;
        }
        return this.isCreated
            ? 'The expense and its related line items were created successfully.'
            : 'The expense was not created. Review the uploaded bill and try again.';
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
