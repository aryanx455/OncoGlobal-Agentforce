import { LightningElement, api, track } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import uploadAndProcessExpenseFile from '@salesforce/apex/ExpenseController.uploadAndProcessExpenseFile';
import getPicklistValues from '@salesforce/apex/MetadataController.getPicklistValues';

const DEFAULT_PROMPT_TEMPLATE = 'Expense_Bill_Extraction';
const EMPTY_DATA = () => ({
    expense_report: {
        employee_name: null,
        employee_id: null,
        doctor_name: null,
        doctor_contact_id: null,
        expense_category: null,
        business_purpose: null
    },
    vendor_details: {
        vendor_name: null,
        vendor_gstin: null,
        vendor_address: null
    },
    invoice_details: {
        invoice_number: null,
        invoice_date: null,
        payment_method: null,
        currency: null
    },
    amount_details: {
        subtotal: null,
        tax: null,
        total_amount: null
    },
    tax_details: {
        cgst: null,
        sgst: null,
        igst: null
    },
    line_items: []
});

export default class ExpenseUpload extends LightningElement {
    @api recordId;
    @api promptTemplateApiName = DEFAULT_PROMPT_TEMPLATE;
    @api agentContextLabel = 'Expense Bill Intake';
    _value;

    @track parsedData = EMPTY_DATA();
    @track lineItems = [];

    contentDocumentId;
    uploadedFileName;
    selectedFile;
    rawJson;
    errorMessage;
    isBusy = false;
    confirmedByUser = false;
    categoryOptions = [];
    lineItemCounter = 0;

    acceptedFormats = '.jpg,.jpeg,.png,.webp,.heic,.heif,.pdf,image/*,application/pdf';
    imageAcceptFormats = 'image/*';

    @api
    get value() {
        return this._value;
    }

    set value(incomingValue) {
        this._value = incomingValue || null;
        if (incomingValue) {
            this.applyAgentInputValue(incomingValue);
        } else {
            this.resetFlow();
        }
    }

    connectedCallback() {
        this.loadPicklistValues();
    }

    @api
    checkValidity() {
        return this.hasParsedData && Boolean(this.contentDocumentId);
    }

    @api
    reportValidity() {
        if (this.checkValidity()) {
            return true;
        }

        this.errorMessage = this.hasParsedData
            ? 'The extracted expense details are ready. Click Submit to create the expense.'
            : 'Upload and analyze an expense bill before submitting.';
        return false;
    }

    @api
    validate() {
        const isValid = this.checkValidity();
        return {
            isValid,
            errorMessage: isValid
                ? null
                : this.hasParsedData
                  ? 'The extracted expense details are ready. Click Submit to create the expense.'
                  : 'Upload and analyze an expense bill before submitting.'
        };
    }

    get uploadRecordId() {
        return this.recordId || USER_ID;
    }

    get hasParsedData() {
        return Boolean(this.rawJson);
    }

    get hasLineItems() {
        return this.lineItems.length > 0;
    }

    get disableSubmit() {
        return this.isBusy || !this.selectedFile || this.hasParsedData;
    }

    get disableConfirm() {
        return this.isBusy || !this.hasParsedData;
    }

    get submitLabel() {
        if (this.hasParsedData) {
            return 'Extracted';
        }
        return this.isBusy ? 'Analyzing' : 'Analyze';
    }

    get confirmLabel() {
        return this.confirmedByUser ? 'Confirmed' : 'Confirm';
    }

    get uploadStatusText() {
        if (this.hasParsedData) {
            return 'Ready to submit';
        }
        if (this.contentDocumentId) {
            return 'File uploaded';
        }
        if (this.selectedFile) {
            return 'File selected';
        }
        return 'Awaiting file';
    }

    get uploadStatusClass() {
        let classes = 'status-pill__indicator';
        if (this.confirmedByUser) {
            classes += ' status-pill__indicator--success';
        } else if (this.hasParsedData || this.contentDocumentId) {
            classes += ' status-pill__indicator--active';
        }
        return classes;
    }

    get extractStepClass() {
        return `timeline__item ${this.contentDocumentId ? 'timeline__item--done' : ''}`;
    }

    get reviewStepClass() {
        return `timeline__item ${this.hasParsedData ? 'timeline__item--done' : ''}`;
    }

    get confirmStepClass() {
        return `timeline__item ${this.confirmedByUser ? 'timeline__item--done' : this.hasParsedData ? 'timeline__item--active' : ''}`;
    }

    get employeeName() {
        return this.parsedData.expense_report.employee_name;
    }

    get employeeId() {
        return this.parsedData.expense_report.employee_id;
    }

    get doctorName() {
        return this.parsedData.expense_report.doctor_name;
    }

    get doctorContactId() {
        return this.parsedData.expense_report.doctor_contact_id;
    }

    get expenseCategory() {
        return this.parsedData.expense_report.expense_category;
    }

    get businessPurpose() {
        return this.parsedData.expense_report.business_purpose;
    }

    get vendorName() {
        return this.parsedData.vendor_details.vendor_name;
    }

    get vendorGstin() {
        return this.parsedData.vendor_details.vendor_gstin;
    }

    get vendorAddress() {
        return this.parsedData.vendor_details.vendor_address;
    }

    get invoiceNumber() {
        return this.parsedData.invoice_details.invoice_number;
    }

    get invoiceDate() {
        return this.parsedData.invoice_details.invoice_date;
    }

    get paymentMethod() {
        return this.parsedData.invoice_details.payment_method;
    }

    get currencyCode() {
        return this.parsedData.invoice_details.currency;
    }

    get subtotal() {
        return this.parsedData.amount_details.subtotal;
    }

    get taxAmount() {
        return this.parsedData.amount_details.tax;
    }

    get totalAmount() {
        return this.parsedData.amount_details.total_amount;
    }

    get cgst() {
        return this.parsedData.tax_details.cgst;
    }

    get sgst() {
        return this.parsedData.tax_details.sgst;
    }

    get igst() {
        return this.parsedData.tax_details.igst;
    }

    loadPicklistValues() {
        getPicklistValues({ objectName: 'Expense__c', fieldName: 'Category__c' })
            .then((result) => {
                this.categoryOptions = result.map((item) => ({
                    label: item.Label,
                    value: item.Value
                }));
            })
            .catch(() => {
                this.categoryOptions = [
                    { label: 'Travel', value: 'Travel' },
                    { label: 'Meals', value: 'Meals' },
                    { label: 'Office Supplies', value: 'Office Supplies' },
                    { label: 'Other', value: 'Other' }
                ];
            });
    }

    handleFileSelected(event) {
        const files = event.target.files || [];
        if (!files.length) {
            this.errorMessage = 'Select a receipt or invoice before analyzing.';
            return;
        }

        const [file] = files;
        this.selectedFile = file;
        this.uploadedFileName = file.name;
        this.contentDocumentId = null;
        this.errorMessage = null;
        this.rawJson = null;
        this.confirmedByUser = false;
        this.resetParsedState();
        this.showToast('File selected', `${file.name} is ready for upload and extraction.`, 'success');
    }

    handleCameraClick() {
        const cameraInput = this.template.querySelector('[data-id="cameraInput"]');
        if (cameraInput) {
            cameraInput.value = null;
            cameraInput.click();
        }
    }

    handleSubmit() {
        if (!this.selectedFile) {
            this.errorMessage = 'Please select a receipt or invoice before submitting.';
            this.showToast('File required', this.errorMessage, 'error');
            return;
        }

        this.errorMessage = null;
        this.isBusy = true;
        this.confirmedByUser = false;

        this.readFileAsBase64(this.selectedFile)
            .then((base64Data) => uploadAndProcessExpenseFile({
                fileName: this.selectedFile.name,
                base64Data,
                contentType: this.selectedFile.type,
                parentRecordId: this.uploadRecordId
            }))
            .then((result) => {
                this.contentDocumentId = result?.contentDocumentId;
                this.uploadedFileName = this.selectedFile?.name || this.uploadedFileName;
                this.selectedFile = null;
                this.rawJson = result?.rawJson;
                this.applyParsedData(result?.payload);
                this.syncAgentValue();
                this.showToast('Extraction complete', 'Review the extracted expense details.', 'success');
            })
            .catch((error) => {
                this.handleServerError(error, 'We could not extract bill details from the uploaded file.');
            })
            .finally(() => {
                this.isBusy = false;
            });
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('The selected file could not be read.'));
            reader.readAsDataURL(file);
        });
    }

    handleConfirm() {
        if (!this.hasParsedData) {
            this.showToast('Nothing to confirm', 'Submit a file for extraction before creating records.', 'error');
            return;
        }

        this.syncAgentValue();
        this.showToast('Details confirmed', 'The confirmed expense data is ready for the agent action.', 'success');
    }

    handleFieldChange(event) {
        const section = event.target.dataset.section;
        const field = event.target.dataset.field;
        const value = this.normalizeFieldValue(event.detail.value, field);
        this.confirmedByUser = this.hasParsedData;

        this.parsedData = {
            ...this.parsedData,
            [section]: {
                ...this.parsedData[section],
                [field]: value
            }
        };
        this.syncAgentValue();
    }

    handleLineItemChange(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = this.normalizeFieldValue(event.detail.value, field);
        this.confirmedByUser = this.hasParsedData;

        this.lineItems = this.lineItems.map((item) => {
            if (item.key !== key) {
                return item;
            }

            const updated = {
                ...item,
                [field]: value
            };

            if (field === 'quantity' || field === 'unit_price') {
                const quantity = Number(updated.quantity) || 0;
                const unitPrice = Number(updated.unit_price) || 0;
                updated.total_price = quantity * unitPrice;
            }

            return updated;
        });
        this.syncAgentValue();
    }

    handleAddLineItem() {
        this.confirmedByUser = this.hasParsedData;
        this.lineItems = [...this.lineItems, this.createLineItem({})];
        this.syncAgentValue();
    }

    handleRemoveLineItem(event) {
        const key = event.currentTarget.dataset.key;
        this.confirmedByUser = this.hasParsedData;
        this.lineItems = this.lineItems.filter((item) => item.key !== key);
        this.syncAgentValue();
    }

    applyParsedData(payload) {
        const merged = {
            ...EMPTY_DATA(),
            ...(payload || {})
        };

        merged.expense_report = {
            ...EMPTY_DATA().expense_report,
            ...(payload?.expense_report || {})
        };
        merged.vendor_details = {
            ...EMPTY_DATA().vendor_details,
            ...(payload?.vendor_details || {})
        };
        merged.invoice_details = {
            ...EMPTY_DATA().invoice_details,
            ...(payload?.invoice_details || {})
        };
        merged.amount_details = {
            ...EMPTY_DATA().amount_details,
            ...(payload?.amount_details || {})
        };
        merged.tax_details = {
            ...EMPTY_DATA().tax_details,
            ...(payload?.tax_details || {})
        };

        this.parsedData = merged;
        this.lineItemCounter = 0;
        this.lineItems = (payload?.line_items || []).map((item) => this.createLineItem(item));
    }

    buildAgentInputValue() {
        return {
            contentDocumentId: this.contentDocumentId || null,
            rawJson: this.rawJson || null,
            employeeName: this.employeeName,
            employeeId: this.employeeId,
            doctorName: this.doctorName,
            doctorContactId: this.doctorContactId,
            expenseCategory: this.expenseCategory,
            businessPurpose: this.businessPurpose,
            vendorName: this.vendorName,
            vendorGstin: this.vendorGstin,
            vendorAddress: this.vendorAddress,
            invoiceNumber: this.invoiceNumber,
            invoiceDate: this.invoiceDate,
            paymentMethod: this.paymentMethod,
            currencyCode: this.currencyCode,
            subtotal: this.toNumberOrNull(this.subtotal),
            taxAmount: this.toNumberOrNull(this.taxAmount),
            totalAmount: this.toNumberOrNull(this.totalAmount),
            cgst: this.toNumberOrNull(this.cgst),
            sgst: this.toNumberOrNull(this.sgst),
            igst: this.toNumberOrNull(this.igst),
            confirmedByUser: this.hasParsedData && Boolean(this.contentDocumentId),
            lineItemsJson: JSON.stringify(
                this.lineItems.map((item) => ({
                    item_name: item.item_name || null,
                    quantity: this.toNumberOrNull(item.quantity),
                    unit_price: this.toNumberOrNull(item.unit_price),
                    total_price: this.toNumberOrNull(item.total_price)
                }))
            )
        };
    }

    syncAgentValue() {
        if (!this.hasParsedData || !this.contentDocumentId) {
            return;
        }

        this.confirmedByUser = true;
        const payload = this.buildAgentInputValue();
        this._value = payload;
        this.dispatchValueChange(payload);
    }

    applyAgentInputValue(value) {
        this.contentDocumentId = value.contentDocumentId || null;
        this.rawJson = value.rawJson || null;
        this.confirmedByUser = value.confirmedByUser === true;
        this.applyParsedData({
            expense_report: {
                employee_name: value.employeeName || null,
                employee_id: value.employeeId || null,
                doctor_name: value.doctorName || null,
                doctor_contact_id: value.doctorContactId || null,
                expense_category: value.expenseCategory || null,
                business_purpose: value.businessPurpose || null
            },
            vendor_details: {
                vendor_name: value.vendorName || null,
                vendor_gstin: value.vendorGstin || null,
                vendor_address: value.vendorAddress || null
            },
            invoice_details: {
                invoice_number: value.invoiceNumber || null,
                invoice_date: value.invoiceDate || null,
                payment_method: value.paymentMethod || null,
                currency: value.currencyCode || null
            },
            amount_details: {
                subtotal: this.toNumberOrNull(value.subtotal),
                tax: this.toNumberOrNull(value.taxAmount),
                total_amount: this.toNumberOrNull(value.totalAmount)
            },
            tax_details: {
                cgst: this.toNumberOrNull(value.cgst),
                sgst: this.toNumberOrNull(value.sgst),
                igst: this.toNumberOrNull(value.igst)
            },
            line_items: this.parseLineItemsJson(value.lineItemsJson)
        });
    }

    parseLineItemsJson(serializedLineItems) {
        if (!serializedLineItems) {
            return [];
        }

        try {
            const parsed = JSON.parse(serializedLineItems);
            return Array.isArray(parsed) ? parsed : [];
        } catch (error) {
            return [];
        }
    }

    createLineItem(item) {
        this.lineItemCounter += 1;
        return {
            key: `line-item-${this.lineItemCounter}`,
            heading: `Line Item ${this.lineItemCounter}`,
            item_name: item.item_name || null,
            quantity: this.toNumberOrNull(item.quantity),
            unit_price: this.toNumberOrNull(item.unit_price),
            total_price:
                this.toNumberOrNull(item.total_price) ??
                ((Number(item.quantity) || 0) * (Number(item.unit_price) || 0))
        };
    }

    normalizeFieldValue(value, fieldName) {
        if (['subtotal', 'tax', 'total_amount', 'cgst', 'sgst', 'igst', 'quantity', 'unit_price', 'total_price'].includes(fieldName)) {
            return this.toNumberOrNull(value);
        }
        return value || null;
    }

    toNumberOrNull(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }

        const parsed = Number(value);
        return Number.isNaN(parsed) ? null : parsed;
    }

    resetParsedState() {
        this.parsedData = EMPTY_DATA();
        this.lineItems = [];
        this.lineItemCounter = 0;
    }

    resetFlow() {
        this.contentDocumentId = null;
        this.uploadedFileName = null;
        this.selectedFile = null;
        this.rawJson = null;
        this.errorMessage = null;
        this.isBusy = false;
        this.confirmedByUser = false;
        this._value = null;
        this.resetParsedState();
    }

    dispatchValueChange(value) {
        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: { value }
            })
        );
    }

    handleServerError(error, fallbackMessage) {
        const message = error?.body?.message || fallbackMessage;
        this.errorMessage = message;
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
