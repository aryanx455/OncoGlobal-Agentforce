# Functional Requirements Document (FRD)
## OncoGlobal Post-Visit Log Agent

**Version:** 1.0  
**Date:** April 2026

---

## 1. Agent Overview

**Agent Name:** Post Visit Log Agent  
**Salesforce API Name:** `PostVisitLogAgent`  
**Type:** `AgentforceEmployeeAgent`  
**Active Version:** v3  
**Language:** English + Hinglish (Hindi-English mix)  
**Entry Point:** Agentforce chat widget embedded in Salesforce app

---

## 2. Core Features

### FR-001: Log Physician Visit

**Trigger phrases:**
- "I visited Dr. [Name] at [Hospital]"
- "Maine Dr. [Name] ke paas gaya tha [Hospital] mein" (Hinglish)
- Any mention of a physician name + hospital + outcome

**Action:** Calls `LogVisitAction` (@InvocableMethod)

**Inputs resolved by agent:**
| Field | Source |
|---|---|
| `transcript` | Full rep utterance |
| `physicianName` | Extracted from speech (e.g. "Dr. Iyer") |
| `hospitalName` | Extracted from speech (e.g. "Tata Memorial") |
| `visitOutcome` | Extracted: Positive/Negative/Neutral/Follow-Up Required |
| `visitType` | Extracted: In-Person Clinic/Hospital Round/Virtual Call/Conference-Event/Drop-In |
| `visitDate` | Today (default) |
| `aiSummary` | Agent-generated summary |
| `engagementScore` | Agent-estimated 0-100 |

**Record created:** `Visit_Report__c`

**Physician resolution logic (in Apex):**
1. Strip "Dr." prefix → wildcard SOQL on Account.Name
2. Filter by RecordType = 'Physician' first
3. If multiple matches, use hospitalName to disambiguate
4. If no match → create placeholder Account (marked for review)

**Output to rep:** Confirmation with visit report ID and physician name resolved

---

### FR-002: Log Visit Expense

**Trigger phrases:**
- "[Amount] rupees ka bill tha" (Hinglish)
- "Lunch was Rs.[Amount]"
- "Spent [Amount] on travel"
- Any mention of rupees/amount + meal/travel/accommodation

**Action:** Calls `LogExpenseAction` (@InvocableMethod)

**Inputs:**
| Field | Required | Notes |
|---|---|---|
| `amount` | Yes | Numeric, Indian Rupees |
| `category` | Yes | Meal/Travel/Accommodation/Samples/CME-Event/Other |
| `physicianName` | No | Used to find visit report |
| `hospitalName` | No | Narrows visit report search |
| `notes` | No | Free text |
| `visitDate` | No | Defaults to today |

**Visit Report resolution:**
1. Search today's Visit_Report__c by physician name + current user
2. If not found → create minimal Visit_Report__c automatically

**Compliance flagging:**
- Trigger `VisitExpenseTrigger` → `VisitExpenseTriggerHandler`
- Sets `Policy_Flag__c = true` if `Amount__c > 150`
- Result returned to agent and surfaced to rep

**Output:** Expense ID + policy flag status

---

### FR-003: Create Follow-Up Tasks

**Trigger phrases:**
- "Bhejna hai" (need to send)
- "Arrange karna hai" (need to arrange)
- "Send [X] to Dr. [Name]"
- "Schedule CME next month"
- "Dobara jaana hai" (need to revisit)
- Any mention of commitment, follow-up, reminder

**Action:** Calls `CreateFollowUpTasksAction` (@InvocableMethod)

**Inputs:**
| Field | Required | Notes |
|---|---|---|
| `followUpActions` | Yes | Comma/newline-separated list |
| `physicianName` | No | Links task to visit report |
| `dueDate` | No | Default: today + 3 days |
| `priority` | No | High/Normal/Low (default: Normal) |

**Parsing logic:**
- Splits on commas, semicolons, newlines, numbered lists
- Strips items < 3 characters
- Truncates subject to 255 chars
- Links to Visit_Report__c via WhatId if found

**Output:** Count of tasks created + Task IDs

---

### FR-004: Extract Discussion Topics

**Trigger:** Agent calls `ExtractTopicsAction` after a visit log

**Purpose:** Parse transcript to identify which drugs were discussed, physician reactions, and key talking points

**Output:** Structured JSON stored in `Discussion_Topics__c` on Visit_Report__c

**Oncology drugs recognized:**
Keytruda (pembrolizumab), Tagrisso (osimertinib), Herceptin (trastuzumab), Opdivo (nivolumab), Iressa (gefitinib), Tarceva (erlotinib), Gleevec (imatinib), Ibrance (palbociclib), Avastin (bevacizumab), Imfinzi (durvalumab), Lynparza (olaparib), Revlimid, Velcade, Zytiga

---

### FR-005: Get Visit Insights

**Trigger:** Rep asks "What's my history with Dr. [Name]?" or similar

**Action:** Calls `GetVisitInsightsAction`

**Returns:** Last visit date, total visits, engagement score trend, drugs discussed, last outcome

---

### FR-006: Hinglish Language Support

**Key phrases the agent must understand:**

| Hinglish | Meaning |
|---|---|
| gaya tha | visited |
| baat ki | discussed |
| positive raha | positive outcome |
| negative gaya | negative outcome |
| rupees ka bill tha | expense amount |
| bhejna hai | need to send (follow-up) |
| arrange karna hai | need to arrange |
| dobara jaana hai | need to revisit |
| follow up banana hai | create follow-up |
| samples diye | gave samples |
| [Drug] ke baare mein baat ki | discussed [Drug] |

---

## 3. Data Model

### Visit_Report__c
| Field | Type | Notes |
|---|---|---|
| `Physician__c` | Lookup (Account) | Required=false — filled by agent |
| `Rep__c` | Lookup (User) | Auto-set to current user |
| `Voice_Transcript__c` | Long Text | Raw rep speech |
| `AI_Summary__c` | Long Text | Agent-generated |
| `Visit_Date__c` | Date | Default today |
| `Visit_Outcome__c` | Picklist | Positive/Negative/Neutral/Follow-Up Required |
| `Visit_Type__c` | Picklist | In-Person Clinic/Hospital Round/Virtual Call/Conference-Event/Drop-In |
| `Engagement_Score__c` | Number (0-100) | Agent-estimated |
| `Discussion_Topics__c` | Long Text | JSON from ExtractTopics |
| `Follow_Up_Actions__c` | Long Text | Parsed action items |
| `Total_Visit_Expense__c` | Roll-up | Sum of Visit_Expense__c |
| `Needs_Review__c` | Checkbox | Set when placeholder physician created |

### Visit_Expense__c
| Field | Type | Notes |
|---|---|---|
| `Visit_Report__c` | Lookup | Required |
| `Amount__c` | Currency (INR) | Required |
| `Category__c` | Picklist | Required |
| `Policy_Flag__c` | Checkbox | Auto-set if > Rs.150 |
| `Notes__c` | Long Text | |
| `Receipt_URL__c` | URL | |

### Account (Physician)
- RecordType: `Physician`
- Custom fields: `Specialty__c`, `Territory__c`, `Last_Visit_Date__c`, `Total_Visits__c`, `Engagement_Score__c`, `Key_Account__c`, `Best_Visit_Time__c`, `Preferred_Visit_Day__c`

---

## 4. Agent Workflow

```
Rep speaks → Agent receives text
    ↓
Step 1: Detect visit description → call LogVisit
    ↓
Step 2: Detect expense mention → call LogExpense (if present)
    ↓
Step 3: Detect follow-up commitments → call CreateFollowUpTasks (if present)
    ↓
Step 4: Confirm all actions in rep's language (English or Hinglish)
```

**Critical rule:** Agent NEVER asks for Salesforce IDs. All lookups happen inside Apex actions.

---

## 5. Error Handling

| Scenario | Behavior |
|---|---|
| Physician not found | Create placeholder Account; set Needs_Review__c |
| Visit Report not found for expense | Create minimal Visit_Report__c automatically |
| DML failure | Return error message; agent says "I tried but hit an issue — confirm doctor name?" |
| Expense > Rs.150 | Log successfully + notify rep of policy flag |
| No actionable items in follow-up text | Return error; agent asks to rephrase |

---

## 6. Non-Functional Requirements

| Requirement | Target |
|---|---|
| Response time | < 5 seconds for action confirmation |
| Availability | Same as Salesforce org SLA |
| Data accuracy | Physician match > 90% accuracy |
| Compliance | All expenses logged; flagging 100% accurate |
| Security | `without sharing` on all action classes (agent runs as requesting user) |
