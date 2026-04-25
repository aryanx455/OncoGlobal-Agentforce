import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import scheduleVisitFromContact from '@salesforce/apex/RepCalendarController.scheduleVisitFromContact';

const CONTACT_FIELDS = [
    'Contact.Name',
    'Contact.Account.Name'
];

function addDays(d, n) {
    const result = new Date(d);
    result.setDate(result.getDate() + n);
    return result;
}

function toISODate(d) {
    return d.toISOString().slice(0, 10);
}

export default class ScheduleVisitAction extends LightningElement {
    @api recordId;

    @track preferredDate;
    @track preferredTime = '10:00';
    @track durationMinutes = 30;
    @track hospitalName = '';
    @track notes = '';
    @track isLoading = false;
    @track isSuccess = false;
    @track successMessage = '';
    @track errorMessage = '';
    @track conflictWarning = '';

    @wire(getRecord, { recordId: '$recordId', fields: CONTACT_FIELDS })
    contact;

    connectedCallback() {
        this.preferredDate = toISODate(addDays(new Date(), 3));
    }

    get contactName() {
        const name = getFieldValue(this.contact.data, 'Contact.Name');
        const account = getFieldValue(this.contact.data, 'Contact.Account.Name');
        if (name && account) return `${name} — ${account}`;
        return name || 'Physician';
    }

    get physicianName() {
        return getFieldValue(this.contact.data, 'Contact.Name') || '';
    }

    get accountName() {
        return getFieldValue(this.contact.data, 'Contact.Account.Name') || '';
    }

    get dur15() { return this.durationMinutes === 15; }
    get dur30() { return this.durationMinutes === 30; }
    get dur45() { return this.durationMinutes === 45; }
    get dur60() { return this.durationMinutes === 60; }

    handleDateChange(e)     { this.preferredDate = e.target.value; }
    handleTimeChange(e)     { this.preferredTime = e.target.value; }
    handleDurationChange(e) { this.durationMinutes = parseInt(e.target.value, 10); }
    handleHospitalChange(e) { this.hospitalName = e.target.value; }
    handleNotesChange(e)    { this.notes = e.target.value; }

    async handleSchedule() {
        this.errorMessage   = '';
        this.conflictWarning = '';
        this.isLoading      = true;

        try {
            const hosp = this.hospitalName || this.accountName;
            const result = await scheduleVisitFromContact({
                contactId:       this.recordId,
                physicianName:   this.physicianName,
                hospitalName:    hosp,
                preferredDate:   this.preferredDate,
                preferredTime:   this.preferredTime,
                durationMinutes: this.durationMinutes,
                notes:           this.notes
            });

            if (result.success === 'true') {
                this.isSuccess      = true;
                this.conflictWarning = result.conflictWarning || '';
                this.successMessage  = `${this.physicianName} ke saath visit ${result.scheduledDateTime} par schedule ho gaya.`
                    + (result.serviceApptId ? ' IAM Service Appointment bhi ban gaya.' : '');
            } else {
                this.errorMessage = result.errorMessage || 'Scheduling failed. Try again.';
            }
        } catch (err) {
            this.errorMessage = err.body?.message || err.message || 'Unexpected error.';
        } finally {
            this.isLoading = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
