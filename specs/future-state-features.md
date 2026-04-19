# OncoGlobal — Future State Features

## Mobile App (Salesforce Mobile / LWC)
Build a mobile-first LWC app for sales reps using Salesforce Mobile SDK / Experience Cloud.
All features below to be surfaced through this app.

---

## 1. Calendar Integration — Visit Scheduling

### What it does
- Agent creates **Salesforce Events** for upcoming doctor visits with agenda
- Syncs to both **rep's calendar** (Salesforce Events → Outlook / Google via Connected App)
- Optionally creates **Physician calendar entry** (if the physician contact has an email)

### Salesforce implementation
- `Event` object: `WhatId = Visit_Report__c`, `WhoId = Contact (physician)`, `OwnerId = Rep User`
- New Agentforce action: `ScheduleVisitAction` → `@InvocableMethod` creates Event with agenda in Description
- Microsoft 365 / Google Workspace Connected App for two-way calendar sync
- Agenda auto-generated from: drug to discuss, last visit outcome, pending follow-up tasks

---

## 2. Email Tracking + Auto-Task Creation

### What it does
- Track reply status on emails sent to physicians (literature, trial data, etc.)
- When email goes unreplied for N days → auto-create Task for rep to follow up
- Rep can say "Send Tagrisso data to Dr. Gupta" → agent sends templated email AND creates tracking task

### Salesforce implementation
- **Einstein Activity Capture** or **Salesforce Inbox** for email tracking
- `EmailMessage` object + `Task` auto-creation via Process Builder / Flow / Apex trigger
- New Agentforce action: `SendPhysicianEmailAction` → sends email from template, logs email, creates follow-up task
- Email templates stored in `EmailTemplate` object keyed by drug name + email type

---

## 3. Mobile App — Vibe Coding Plan

### Stack
- **Salesforce Experience Cloud** OR standalone LWC Off-Platform (Salesforce Mobile SDK)
- OR: Lightning Web Components deployed on Salesforce Mobile App
- React Native bridge (Salesforce Mobile SDK) for native mic access

### Key screens
1. **Home Dashboard**: Today's visits, pending tasks, recent expenses
2. **Voice Log Screen**: Big mic button → Web Speech API → PostVisitLogAgent
3. **Visit Detail**: Full visit report, discussion topics, linked expenses, follow-up tasks
4. **Calendar View**: Upcoming visits with agenda, sync status
5. **Expense Tracker**: Expense list, policy flag alerts, receipt upload
6. **Physician Profile**: Visit history, engagement score trend, last discussion topics

### Agentforce integration in mobile
- Call agent via `einstein/ai/v1/agents/{agentId}/sessions` REST endpoint
- Stream responses for real-time voice-to-text-to-action UX
- Push notifications for: overdue follow-ups, calendar reminders, email reply alerts

---

## 4. Record Creation on Behalf of Rep

### Already implemented (current state)
- `Visit_Report__c`: `Rep__c = UserInfo.getUserId()` — always the logged-in rep
- `Visit_Expense__c`: Linked to visit report
- `Task`: `OwnerId = UserInfo.getUserId()` — assigned to the rep
- Placeholder `Account` created if physician not found

### Future enhancements
- Create `Contact` records for physicians (not just Account)
- Create `Opportunity` records when physician shows strong interest
- Create `Campaign Member` records for CME event tracking

---

## 5. ABDM HFR Integration (already coded, parked)

See: `force-app/main/default/classes/ABDMHFRService.cls`
- Enrich physician Account from ABDM Health Facility Registry
- Named Credential: `ABDM_HFR`
- Account fields: `HFR_Facility_ID__c`, `HFR_Verified__c`, `HFR_Facility_Type__c`, `Geolocation__c`
- Deploy when ABDM sandbox credentials are available

---

## Priority for Next Session

1. Fix Agent Access (permission set / profile) → re-run tests to verify actions fire
2. ScheduleVisitAction Apex class + Agentforce function
3. Mobile LWC scaffold (voice mic button screen)
4. Calendar sync Connected App setup
5. Email tracking action
6. ABDM HFR deploy
