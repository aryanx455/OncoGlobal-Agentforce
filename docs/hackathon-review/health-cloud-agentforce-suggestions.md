# Health Cloud + Agentforce Suggestion Report

Date: 2026-04-25

## Purpose

This document reviews the current Onco Global Agentforce repo and connected hackathon org against the Post-Visit Log Agent challenge. It also captures Salesforce Health Cloud and Agentforce guidance from official Salesforce sources, then turns that into implementation-ready suggestions.

The goal is not to rewrite everything. The goal is to make the existing functionality feel like one polished healthcare field-ops product:

- A sales executive speaks or types a post-visit update.
- Agentforce creates the visit report, summaries, follow-up tasks, and expenses.
- Receipt upload/photo upload is handled through the agent UI.
- Doctor, hospital, relationship history, and expense data connect to Health Cloud-friendly provider objects.
- No action depends on hardcoded org IDs, prompt names, sample doctors, or manual demo-only assumptions.

## Official Salesforce Guidance That Matters

Salesforce positions Health Cloud as a healthcare-specific platform that connects clinical and non-clinical data, healthcare data models, workflows, interoperability, compliance, and AI agents. For this hackathon, that means the strongest story is not just "we made custom objects." The stronger story is "we use Agentforce on top of a healthcare/provider relationship data model to reduce field-team admin burden."

Useful Health Cloud benefits for our pitch:

- Health Cloud supports connected care and operational workflows by rallying teams around a single view of patients, members, and partners.
- Health Cloud includes provider and facility-oriented data models, including Provider Relationship Management.
- Provider Network Management focuses on improving provider onboarding, network relationships, provider satisfaction, and operational efficiency.
- Health Cloud has standard healthcare objects and concepts such as Healthcare Provider, Healthcare Facility, Service Appointment, Provider Relationship Management, Intelligent Appointment Management, and Data 360 for Health.
- Intelligent Document Automation and Agentforce are relevant to the receipt/invoice upload idea because our agent is already extracting data from documents and turning it into structured Salesforce records.

Useful Agentforce guidance for our implementation:

- Agentforce actions are the building blocks that let an agent perform tasks and interact with Salesforce data.
- Custom actions can be built from Apex invocable methods, Apex REST, AuraEnabled methods, flows, prompt templates, named queries, and enhanced UI types.
- Apex invocable actions are appropriate when the agent needs deterministic business logic, validation, record creation, and multi-step orchestration.
- Lightning Types/custom UI are the right direction for complex interaction like uploading a receipt, reviewing extracted values, and confirming before record creation.

## Current Repo + Org Reality

The repo already has a strong hackathon foundation:

- Agentforce authoring bundle for a Post Visit Log Agent.
- Apex actions for visit logging, expense logging, follow-up task creation, medical context, visit insights, scheduling, and receipt extraction.
- Custom objects for `Visit_Report__c`, `Visit_Expense__c`, `Expense__c`, and `Expense_Line_Item__c`.
- Mobile/voice-oriented LWCs and a receipt upload LWC.
- WhatsApp webhook scaffold.
- OncoGlobal app tabs, layouts, permission set, and tests.

The connected org also contains key objects needed for the challenge:

- `HealthcareProvider`
- `HealthcareFacility`
- `ServiceAppointment`
- `MessagingSession`
- `MessagingEndUser`
- `Visit_Report__c`
- `Visit_Expense__c`
- `Expense__c`
- `Expense_Line_Item__c`

Important org drift found during review:

- Active org agent versions are `PostVisitLogAgent v10` and `ExpenseUploadAgent v6`.
- Git contains newer source artifacts for the Post Visit agent, but `PostVisitLogAgent_v21` does not include the expense upload topic.
- Recent uploaded `Expense__c` records exist, but the doctor lookup is blank on uploaded examples.
- Upload-based expenses currently create `Expense__c`; conversational expenses create `Visit_Expense__c`. That splits the story and makes reporting harder.

## Recommended Product Story

Position the solution as:

**Onco Field Copilot: an Agentforce-powered Health Cloud assistant for sales executives after physician visits.**

The agent should support three modes:

- Before visit: "Brief me on Dr. Mehta before I meet him."
- During or after visit: "Log my visit with Dr. Mehta. He asked for lung cancer trial material and wants a lunch next week."
- Admin wrap-up: "Upload this expense bill" or "I spent Rs. 450 on lunch with Dr. Mehta."

This directly maps to the challenge requirements:

- Voice-to-record logging.
- Automated task creation.
- Expense management.
- Physician relationship insights.
- Digital engagement path through WhatsApp/SMS.
- Mobile-first experience.
- Health Cloud provider/facility relationship model.

## Highest-Priority Object Changes

### 1. Make `Visit_Report__c` the central transaction

Keep `Visit_Report__c` as the core post-visit record. Everything else should connect back to it where possible.

Recommended fields:

| Object | Field | Type | Why |
| --- | --- | --- | --- |
| `Visit_Report__c` | `Source_Channel__c` | Picklist: Agentforce, Mobile Voice, WhatsApp, Manual | Shows omnichannel capture. |
| `Visit_Report__c` | `Raw_Input_Type__c` | Picklist: Voice, Text, Image, PDF, Mixed | Helps demo voice/document intake. |
| `Visit_Report__c` | `Agent_Session_Id__c` | Text | Ties multi-turn agent flow to records without hardcoding. |
| `Visit_Report__c` | `Extraction_Confidence__c` | Percent/Number | Shows AI confidence and review readiness. |
| `Visit_Report__c` | `Relationship_Score_Snapshot__c` | Number | Captures score at visit time. |
| `Visit_Report__c` | `Referral_Potential__c` | Picklist: High, Medium, Low | Helps ROI/relationship tracking. |
| `Visit_Report__c` | `Follow_Up_Status__c` | Picklist: None, Pending, In Progress, Complete | Connects visit summary to execution. |
| `Visit_Report__c` | `Review_Status__c` | Picklist: Draft, Needs Review, Confirmed | Better than only a checkbox for AI-generated data. |

Existing fields `Prescriber__c`, `Hospital__c`, `Needs_Review__c`, `Visit_Type__c`, and `Total_Visit_Expense__c` are good and should stay.

### 2. Align doctors and hospitals with Health Cloud objects

Right now the project mostly models doctors and hospitals through `Contact` and `Account`. That is fine for Salesforce basics, but the challenge specifically asks for Health Cloud.

Recommended approach:

- Keep `Contact` as the human doctor/prescriber record because the existing code already works with it.
- Keep `Account` as the clinic/hospital/business relationship record because current triggers and rollups already use it.
- Add optional Health Cloud-alignment lookup `Visit_Report__c.Healthcare_Provider__c` to `HealthcareProvider` if the org supports it cleanly.
- Add optional Health Cloud-alignment lookup `Visit_Report__c.Healthcare_Facility__c` to `HealthcareFacility` if the org supports it cleanly.
- Add optional Health Cloud-alignment lookup `Contact.Healthcare_Provider__c` to `HealthcareProvider` if the org supports it cleanly.
- Add optional Health Cloud-alignment lookup `Account.Healthcare_Facility__c` to `HealthcareFacility` if the org supports it cleanly.
- Use the Health Cloud fields in the UI/demo even if Account/Contact remain the operational backing model.

This gives us both reliability and Health Cloud credibility.

### 3. Unify expense data

Current split:

- Agent typed expense creates `Visit_Expense__c`.
- Receipt upload creates `Expense__c` and `Expense_Line_Item__c`.

Recommended path:

- Make `Visit_Expense__c` the primary expense record for the post-visit agent.
- Add receipt extraction fields to `Visit_Expense__c` instead of keeping a disconnected `Expense__c` flow.
- If `Expense__c` must stay, add a lookup from `Expense__c` to `Visit_Report__c` and/or create a matching `Visit_Expense__c` after upload confirmation.

Recommended fields:

| Object | Field | Type | Why |
| --- | --- | --- | --- |
| `Visit_Expense__c` | `Vendor__c` | Text | Needed for invoice upload. |
| `Visit_Expense__c` | `Invoice_Number__c` | Text | Duplicate prevention and audit. |
| `Visit_Expense__c` | `Invoice_Date__c` | Date | Expense compliance and reporting. |
| `Visit_Expense__c` | `Receipt_Content_Document_Id__c` | Text(18) | Stores linked file ID without fragile URL-only design. |
| `Visit_Expense__c` | `Extraction_Confidence__c` | Percent/Number | Lets the agent require user confirmation on low confidence. |
| `Visit_Expense__c` | `Extracted_JSON__c` | Long Text Area | Auditable AI extraction payload. |
| `Visit_Expense__c` | `Duplicate_Key__c` | Text, External ID/Unique if possible | Prevents duplicate uploads of same bill. |
| `Visit_Expense__c` | `Approval_Status__c` | Picklist: Draft, Submitted, Approved, Rejected, Needs Review | Makes expenses feel production-like. |
| `Visit_Expense__c` | `Policy_Reason__c` | Text | Explain why a bill was flagged. |

For line items:

- Either rename `Expense_Line_Item__c` to make it visit-expense aware, or add `Visit_Expense__c` lookup to it.
- Populate `Total_Price__c`; it currently exists but is not consistently part of the upload creation story.
- Add `Tax_Amount__c` and `HSN_or_SAC__c` only if the receipt extraction prompt can reliably return them.

### 4. Improve provider relationship analytics

To impress judges, do not stop at "record created." Add relationship intelligence.

Recommended fields:

| Object | Field | Type | Why |
| --- | --- | --- | --- |
| `Contact` | `Specialty__c` | Picklist/Text | Helps doctor matching and insights. |
| `Contact` | `Primary_Hospital__c` | Lookup Account | Shows physician-facility relationship. |
| `Contact` | `Preferred_Visit_Day__c` | Picklist | Useful before-meeting brief. |
| `Contact` | `Preferred_Visit_Time__c` | Text/Picklist | Useful before-meeting brief. |
| `Contact` | `Relationship_Score__c` | Number | Existing insight field should be visible and updated. |
| `Contact` | `Last_Referral_Date__c` | Date | Directly supports "last referral from this clinic." |
| `Contact` | `Referral_Count__c` | Number/Rollup-like | Demonstrates ROI. |
| `Account` | `Territory__c` | Text/Picklist | Helps route planning. |
| `Account` | `Facility_Type__c` | Picklist: Hospital, Clinic, Diagnostic Center, Other | Better Health Cloud-friendly segmentation. |

## Agentforce Improvements With No Hardcoding

### 1. Add a deterministic orchestration action

Instead of relying on the agent to guess the perfect action sequence every time, create one composite Apex action:

`PostVisitOrchestratorAction`

Inputs:

- transcript
- physician name
- hospital/facility name
- visit date
- expense amount/category if mentioned
- uploaded content document ID if present
- channel
- agent session ID

Responsibilities:

- Resolve doctor/provider and hospital/facility.
- Create or update `Visit_Report__c`.
- Extract topics and next best action.
- Create follow-up tasks.
- Log typed expense if present.
- Link uploaded receipt extraction if present.
- Return a compact confirmation card for Agentforce.

This keeps Agentforce conversational while Apex handles deterministic sequencing.

### 2. Create a reusable provider resolver

Create a single service:

`ProviderResolutionService`

It should resolve:

- doctor by Contact name
- doctor by Account name if older data uses Account
- hospital/facility by Account name
- optional HealthcareProvider/HealthcareFacility link
- ambiguous matches with confidence and review status

No hardcoded doctor names. No hardcoded IDs. If the match is weak, create a draft contact/account and mark the visit `Needs_Review__c = true`.

### 3. Replace hardcoded prompt template names

Current risk:

- `ExpenseController` references `Expense_Bill_Extraction`.
- `SocialMediaPostsController` hardcodes `extract_data_from_invoice`.

Recommended fix:

- Add custom metadata such as `Agentforce_Config__mdt`.
- Store prompt template API names there, such as `ExpenseExtractionPrompt`, `VisitSummaryPrompt`, and `TopicExtractionPrompt`.
- Apex reads config at runtime.
- Tests inject or mock the value.

This makes the repo portable across orgs and branches.

### 4. Use Agentforce topics as business capabilities

Recommended topics:

- `post_visit_log`: handles visit summary, doctor, hospital, outcome, engagement score.
- `follow_up_tasks`: creates follow-up tasks from summary.
- `expense_log`: handles typed expenses.
- `expense_bill_upload`: handles file/image/PDF upload through Lightning Type UI.
- `physician_insights`: gives before-meeting provider brief.
- `schedule_visit`: creates Event and, where possible, ServiceAppointment.
- `digital_engagement_intake`: handles WhatsApp/SMS handoff and creates the same records as the mobile agent.

Each topic should expose only the actions it needs. Avoid putting every action in every topic.

### 5. Use confirmation gates for AI-created records

Agentforce should confirm before creating or finalizing:

- visit report if doctor/facility resolution confidence is low
- expense if amount, vendor, invoice number, date, or doctor is missing
- follow-up tasks if more than three tasks are detected
- duplicate invoice if the duplicate key already exists

This makes the AI feel safe and professional.

## Health Cloud Demo Enhancements

These are high-impact but still realistic for a hackathon:

### Before-meeting brief

User asks:

`Brief me on Dr. Mehta before my visit.`

Agent answers:

- last visit summary
- last follow-up tasks
- open tasks
- last expense/meeting context
- relationship score
- referral trend
- recommended talking points

### Provider relationship graph

Use Account, Contact, HealthcareProvider, HealthcareFacility, and Account Contact Relationship or equivalent relationship records to show:

- doctor belongs to or practices at a facility
- rep has visit history with doctor
- doctor has referral potential
- facility has total engagement/expense rollups

### Smart route/day planning

Use existing calendar and scheduling code:

- "Plan my visits for tomorrow in South Mumbai."
- Agent returns suggested doctors based on last visit age, preferred visit time, relationship score, and pending follow-ups.

### Receipt snap with doctor context

When the user uploads a bill:

- UI asks/selects doctor if not inferred.
- Apex links the expense to the current or most recent visit.
- Duplicate check prevents two records for the same invoice.
- Extracted line items are shown in a compact mobile layout.

### WhatsApp media flow

Current WhatsApp text scaffold is useful, but the hackathon requirement mentions photo receipts. Upgrade path:

- Verify inbound webhook authenticity.
- Accept media URL or messaging attachment.
- Store the file as `ContentVersion`.
- Reuse the same `ExpenseController` extraction flow.
- Create or update `Visit_Report__c`/`Visit_Expense__c`.

## Security + Reliability Suggestions

- Review classes marked `without sharing`; use `with sharing` unless bypassing sharing is intentional and documented.
- Add CRUD/FLS checks or security-reviewed service boundaries for user-driven DML.
- Add permission set field access for every custom field used by Apex and LWC, especially `Visit_Report__c.Prescriber__c` and `Visit_Report__c.Hospital__c`.
- Add validation to prevent blank `Expense__c` records.
- Add duplicate prevention for uploaded invoices.
- Add clear error messages from Apex back to the Agentforce UI.
- Ensure prompt templates and active agent versions are either metadata-deployed or documented as manual setup.

## Suggested Implementation Order

### Phase 1: Stabilize demo

- Align git with the active org agent version.
- Ensure `PostVisitLogAgent` includes the upload topic in the active version.
- Fix prompt template API-name mismatch.
- Add missing permission-set field permissions.
- Make uploaded expense require amount, vendor/category, date, and doctor or review status.

### Phase 2: Unify data model

- Link `Expense__c` to `Visit_Report__c`, or move upload creation to `Visit_Expense__c`.
- Add receipt metadata fields to `Visit_Expense__c`.
- Add duplicate key and approval/review status.
- Populate line item totals.

### Phase 3: Health Cloud credibility

- Add optional HealthcareProvider/HealthcareFacility links.
- Show HealthcareProvider and HealthcareFacility tabs/pages in the demo.
- Add provider relationship/briefing action using existing visit history.
- Add facility/doctor rollups to show outreach ROI.

### Phase 4: Innovation layer

- Add route planning.
- Upgrade WhatsApp media intake.
- Add a mobile "field cockpit" UI: record visit, snap receipt, see doctor brief, open tasks.
- Add a simple Data Cloud/relationship intelligence story if time allows.

## Object Recommendation Summary

Recommended core model:

- `Visit_Report__c`: central post-visit record.
- `Visit_Expense__c`: primary expense record tied to a visit.
- `Expense_Line_Item__c`: child line items tied to the primary expense model.
- `Contact`: individual doctor/prescriber.
- `Account`: hospital/clinic/facility and optionally physician account if legacy data uses it.
- `HealthcareProvider`: Health Cloud provider alignment.
- `HealthcareFacility`: Health Cloud facility alignment.
- `Task`: follow-up actions.
- `Event` and `ServiceAppointment`: scheduling and intelligent appointment story.
- `ContentDocument`: receipt/image/PDF storage.

Recommended decision:

Use `Visit_Expense__c` as the primary expense object for the hackathon demo. Keep `Expense__c` only if it becomes a staging/legacy upload object or if we explicitly link it back to `Visit_Report__c`.

## Sources

- Salesforce Health Cloud overview: https://www.salesforce.com/healthcare/cloud/
- Salesforce Agentforce Actions developer guide: https://developer.salesforce.com/docs/ai/agentforce/guide/get-started-actions.html
- Salesforce Apex InvocableMethod Agentforce action guide: https://developer.salesforce.com/docs/ai/agentforce/guide/agent-invocablemethod.html
- Salesforce Health Cloud overview data model: https://developer.salesforce.com/docs/platform/data-models/guide/health-cloud-overview.html
- Salesforce Provider Relationship Management data model: https://developer.salesforce.com/docs/platform/data-models/guide/provider-relationship-management.html
- Salesforce Provider Network Management help: https://help.salesforce.com/s/articleView?id=ind.admin_provider_network_management.htm&type=5
- Salesforce Health Cloud admin help: https://help.salesforce.com/s/articleView?id=ind.healthcare_admin.htm&type=5
