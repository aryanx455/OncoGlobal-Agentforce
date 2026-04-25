# Technical Architecture
## OncoGlobal Post-Visit Log Agent

---

## 1. System Overview

```
┌─────────────────────────────────────────────────────────┐
│                 Salesforce Org (Hackathon Sandbox)       │
│                                                         │
│  ┌──────────────┐    ┌─────────────────────────────┐   │
│  │  Agentforce  │    │     Agentforce Runtime       │   │
│  │  Chat Widget │───▶│  PostVisitLogAgent (Bot v3)  │   │
│  │  (UI)        │    │  + GenAiPlannerBundle        │   │
│  └──────────────┘    │  + Post_Visit_Log_Plugin     │   │
│                      │  + 6 GenAiFunctions           │   │
│                      └──────────┬──────────────────-─┘   │
│                                 │ @InvocableMethod calls  │
│                      ┌──────────▼──────────────────-─┐   │
│                      │      Apex Action Classes        │   │
│                      │  • LogVisitAction               │   │
│                      │  • LogExpenseAction             │   │
│                      │  • CreateFollowUpTasksAction    │   │
│                      │  • ExtractTopicsAction          │   │
│                      │  • GetVisitInsightsAction       │   │
│                      │  • GetMedicalContextAction      │   │
│                      └──────────┬──────────────────-─┘   │
│                                 │ DML / SOQL              │
│                      ┌──────────▼──────────────────-─┐   │
│                      │       Salesforce Data           │   │
│                      │  • Visit_Report__c              │   │
│                      │  • Visit_Expense__c             │   │
│                      │  • Task (standard)              │   │
│                      │  • Account (Physician)          │   │
│                      └─────────────────────────────-──┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Agentforce Metadata Chain

```
Bot (PostVisitLogAgent)
 └── BotVersion v3 [ACTIVE]
      └── conversationDefinitionPlanners
           └── GenAiPlannerBundle (PostVisitLogAgent)
                └── GenAiPlugin (Post_Visit_Log_Plugin)  [Topic]
                     ├── GenAiFunction: LogVisit          → LogVisitAction.cls
                     ├── GenAiFunction: LogExpense        → LogExpenseAction.cls
                     ├── GenAiFunction: CreateFollowUpTasks → CreateFollowUpTasksAction.cls
                     ├── GenAiFunction: ExtractTopics     → ExtractTopicsAction.cls
                     ├── GenAiFunction: GetVisitInsights  → GetVisitInsightsAction.cls
                     └── GenAiFunction: GetMedicalContext → GetMedicalContextAction.cls
```

---

## 3. Apex Action Classes

### LogVisitAction.cls
- **Trigger:** Rep mentions visiting a physician
- **Key logic:**
  - `resolvePhysician(name, hospital)` — SOQL wildcard on Account.Name, RecordType=Physician, disambiguate by hospital
  - `createPlaceholderAccount(name, hospital)` — fallback if not found
  - Inserts `Visit_Report__c` with all extracted fields
- **Sharing:** `without sharing` (agent runs as requesting user)

### LogExpenseAction.cls
- **Trigger:** Rep mentions an expense amount
- **Key logic:**
  - `findOrCreateVisitReport(physician, hospital, date)` — finds today's report or creates minimal one
  - Inserts `Visit_Expense__c`
  - Re-queries after insert to get trigger-set `Policy_Flag__c`
- **Policy:** Rs.150 limit enforced by `VisitExpenseTriggerHandler`

### CreateFollowUpTasksAction.cls
- **Trigger:** Rep mentions commitments/follow-ups
- **Key logic:**
  - `parseActions(rawText)` — splits on commas, semicolons, newlines, numbered lists
  - Batch insert of Task records
  - Links to Visit_Report__c via WhatId
- **Due date:** Default today + 3 days

### ExtractTopicsAction.cls
- Parses transcript for drug names and physician reactions
- Stores structured JSON in `Discussion_Topics__c`

### GetVisitInsightsAction.cls
- Queries Visit_Report__c history for a physician
- Returns: last visit, total visits, engagement trend, drugs discussed

### GetMedicalContextAction.cls
- Returns oncology drug context and physician specialty information

---

## 4. Triggers

### VisitExpenseTrigger → VisitExpenseTriggerHandler
- **Event:** Before/After insert, before update
- **Logic:** Sets `Policy_Flag__c = true` if `Amount__c > 150`

### VisitReportTrigger → VisitReportTriggerHandler
- **Event:** After insert, after update
- **Logic:** Updates `Last_Visit_Date__c` and `Total_Visits__c` on Account

---

## 5. Deploy Map

### What CAN be deployed via CLI (`sf project deploy start`)
| Component | Dir | Notes |
|---|---|---|
| Apex Classes | `force-app/main/default/classes` | All action classes + tests |
| Custom Objects | `force-app/main/default/objects` | Visit_Report__c, Visit_Expense__c, Account fields |
| Triggers | `force-app/main/default/triggers` | |
| Permission Sets | `force-app/main/default/permissionsets` | |
| GenAiFunctions | `force-app/main/default/genAiFunctions` | Deployable on CLEAN slate |
| GenAiPlugin | `force-app/main/default/genAiPlugins` | Deployable on CLEAN slate |
| GenAiPlannerBundle | `force-app/main/default/genAiPlannerBundles` | Deployable on CLEAN slate |

### What CANNOT be deployed via CLI (Builder UI only)
| Component | Reason | Fix |
|---|---|---|
| BotVersion (update existing) | Platform lock (-1806600421) | Create new version instead |
| BotVersion (new) | Must move other versions out of dir first, then activate with `sf agent activate` |
| Action wiring inside topic | Builder-managed UI step | Add actions manually in Builder → Topics |

### Deploying a New BotVersion (workaround)
```bash
# 1. Create new file: vN.botVersion-meta.xml
# 2. Move ALL other versions to temp dir (NOT just rename in-place):
Move-Item v1.botVersion-meta.xml C:\Temp\sf_bak\
Move-Item v2.botVersion-meta.xml C:\Temp\sf_bak\
# etc.

# 3. Deploy
sf project deploy start --source-dir force-app/main/default/bots --target-org hackathon-sandbox

# 4. Activate
sf agent activate --api-name PostVisitLogAgent --version N --target-org hackathon-sandbox

# 5. Restore temp files
Move-Item C:\Temp\sf_bak\v*.botVersion-meta.xml force-app/main/default/bots/PostVisitLogAgent/
```

---

## 6. Target Org

| Setting | Value |
|---|---|
| Alias | `hackathon-sandbox` |
| URL | `https://orgfarm-a5659b3ee2--hackathon.sandbox.my.salesforce.com` |
| Username | `epic.3b626442ef46@orgfarm.salesforce.com.hackathon` |
| API Version | 66.0 |
| Type | OrgFarm Hackathon Sandbox |

**⚠️ There is also `d360-sandbox` (yousuf61-dev-ed) — this is the WRONG org. Always use `hackathon-sandbox`.**

---

## 7. File Structure

```
OncoGlobal-Agentforce/
├── CLAUDE.md                          # LLM context (read automatically by Claude Code)
├── docs/
│   ├── BRD.md                         # Business requirements
│   ├── FRD.md                         # Functional requirements
│   ├── ARCHITECTURE.md                # This file
│   └── AGENT_COLLABORATION.md         # Instructions for LLM contributors
├── force-app/main/default/
│   ├── bots/PostVisitLogAgent/        # Bot + BotVersions v1/v2/v3
│   ├── classes/                       # All Apex action classes + tests
│   ├── genAiFunctions/                # 6 GenAiFunction definitions
│   ├── genAiPlugins/                  # Post_Visit_Log_Plugin
│   ├── genAiPlannerBundles/           # PostVisitLogAgent planner
│   ├── objects/                       # Visit_Report__c, Visit_Expense__c, Account fields
│   ├── triggers/                      # VisitExpense + VisitReport triggers
│   └── permissionsets/                # OncoGlobal_Access
└── specs/
    ├── PostVisitLogAgent-testSpec.yaml # Agent test cases
    └── future-state-features.md       # Phase 2+ features
```
