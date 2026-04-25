import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getCalendarData from '@salesforce/apex/RepCalendarController.getCalendarData';
import USER_ID from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

const MONTH_NAMES = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
];
const DAY_NAMES = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

function padZero(n) { return n < 10 ? '0' + n : '' + n; }

function toDateStr(year, month, day) {
    return `${year}-${padZero(month + 1)}-${padZero(day)}`;
}

function outcomeClass(outcome) {
    if (outcome === 'Positive')            return 'entry-card entry-pos';
    if (outcome === 'Negative')            return 'entry-card entry-neg';
    if (outcome === 'Follow-Up Required')  return 'entry-card entry-fu';
    return 'entry-card entry-neutral';
}

function visitDotClass(entries) {
    const outcomes = entries.map(e => e.outcome);
    if (outcomes.includes('Negative'))           return 'dot dot-neg';
    if (outcomes.includes('Follow-Up Required')) return 'dot dot-fu';
    if (outcomes.includes('Positive'))           return 'dot dot-pos';
    return 'dot dot-neutral';
}

export default class OncoRepCalendar extends LightningElement {
    @track currentYear;
    @track currentMonth;
    @track calDays = [];
    @track selectedDateStr = null;
    @track selectedDayEntries = [];
    @track selectedDayLabel = '';
    @track upcomingEntries = [];
    @track recentEntries = [];
    @track isLoading = true;
    @track hasError = false;

    _allEntries = [];
    _entryMap   = {};      // dateStr → CalendarEntry[]
    repName     = 'My Visits';
    dayHeaders  = DAY_NAMES;

    connectedCallback() {
        const now = new Date();
        this.currentYear  = now.getFullYear();
        this.currentMonth = now.getMonth();
    }

    @wire(getCalendarData)
    wiredData({ data, error }) {
        this.isLoading = false;
        if (data) {
            this._allEntries = data.map(e => ({
                ...e,
                cardClass: e.type === 'event' ? 'entry-card entry-event' : outcomeClass(e.outcome)
            }));
            this._buildEntryMap();
            this.upcomingEntries = this._allEntries.filter(e => !e.isPast);
            this.recentEntries   = this._allEntries.filter(e => e.isPast);
            this._buildCalendar();
        } else if (error) {
            this.hasError = true;
        }
    }

    _buildEntryMap() {
        this._entryMap = {};
        this._allEntries.forEach(e => {
            const key = e.dateKey;
            if (!this._entryMap[key]) this._entryMap[key] = [];
            this._entryMap[key].push(e);
        });
    }

    _buildCalendar() {
        const year  = this.currentYear;
        const month = this.currentMonth;
        const firstDow    = new Date(year, month, 1).getDay();   // 0=Sun
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const todayStr    = toDateStr(
            new Date().getFullYear(), new Date().getMonth(), new Date().getDate()
        );

        const cells = [];

        // Leading blank cells
        for (let i = 0; i < firstDow; i++) {
            cells.push({ key: `blank-${i}`, dayNum: '', dateStr: '', cellClass: 'cal-cell cal-blank' });
        }

        // Month days
        for (let d = 1; d <= daysInMonth; d++) {
            const dateStr = toDateStr(year, month, d);
            const entries = this._entryMap[dateStr] || [];
            const hasEvent = entries.some(e => e.type === 'event');
            const hasVisit = entries.some(e => e.type === 'visit');
            const isToday  = dateStr === todayStr;
            const isSelected = dateStr === this.selectedDateStr;

            let cellClass = 'cal-cell';
            if (isToday)    cellClass += ' cal-today';
            if (isSelected) cellClass += ' cal-selected';
            if (!isToday && !isSelected && entries.length > 0) cellClass += ' cal-has-entry';

            cells.push({
                key:          dateStr,
                dayNum:       d,
                dateStr,
                cellClass,
                hasEvent,
                hasVisit,
                visitDotClass: hasVisit ? visitDotClass(entries.filter(e => e.type === 'visit')) : ''
            });
        }

        this.calDays = cells;
    }

    get monthLabel() {
        return `${MONTH_NAMES[this.currentMonth]} ${this.currentYear}`;
    }

    get hasAnyData() {
        return this._allEntries.length > 0;
    }

    prevMonth() {
        if (this.currentMonth === 0) {
            this.currentMonth = 11;
            this.currentYear -= 1;
        } else {
            this.currentMonth -= 1;
        }
        this.selectedDateStr = null;
        this.selectedDayEntries = [];
        this._buildCalendar();
    }

    nextMonth() {
        if (this.currentMonth === 11) {
            this.currentMonth = 0;
            this.currentYear += 1;
        } else {
            this.currentMonth += 1;
        }
        this.selectedDateStr = null;
        this.selectedDayEntries = [];
        this._buildCalendar();
    }

    handleDayClick(evt) {
        const dateStr = evt.currentTarget.dataset.date;
        if (!dateStr) return;

        if (this.selectedDateStr === dateStr) {
            this.selectedDateStr    = null;
            this.selectedDayEntries = [];
        } else {
            this.selectedDateStr    = dateStr;
            this.selectedDayEntries = this._entryMap[dateStr] || [];

            const [y, m, d] = dateStr.split('-');
            const dt = new Date(Number(y), Number(m) - 1, Number(d));
            this.selectedDayLabel = dt.toLocaleDateString('en-IN', {
                weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
            });
        }
        this._buildCalendar();
    }
}
