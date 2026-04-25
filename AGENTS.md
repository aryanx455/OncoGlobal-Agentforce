# OncoGlobal Agentforce — Project Context

## What This Is
Salesforce Agentforce solution for OncoGlobal (Indian pharma company) hackathon.
A voice-first AI agent that lets medical reps log physician visits, expenses, and follow-up tasks by speaking naturally after a visit — in English or Hinglish.

## Git Workflow Rules
This repo is shared by Aryan and Avi. Protect `main`; never commit or push directly to `main`.

Every change must use this flow:
```bash
git checkout main
git pull origin main
git checkout -b avi/<short-feature-name>
# make one focused feature change
git push origin avi/<short-feature-name>
gh pr create --title "..." --body "..."
```

Rules:
- Use one PR per feature. Do not bundle unrelated changes.
- Branch naming: `avi/expense-upload`, `avi/data-model-fix`, `avi/prompt-template`, etc.
- Commit messages must explain what changed and why.
- Never force-push to `main`.
- Aryan reviews Avi's PRs before merge.
- Before opening a PR, verify Apex compile/deploy checks, no hardcoded org IDs or credentials, deployed object/field API names match `hackathon-sandbox`, and update `CLAUDE.md` when deployed component status changes.

## Target Org
- **Alias:** `hackathon-sandbox`
- **URL:** `https://orgfarm-a5659b3ee2--hackathon.sandbox.my.salesforce.com`
- **Username:** `epic.3b626442ef46@orgfarm.salesforce.com.hackathon`
- **Type:** OrgFarm Hackathon Sandbox
- **API Version:** 66.0

> There is also a `d360-sandbox` (yousuf61-dev-ed.my.salesforce.com) — this is the WRONG org. Always target `hackathon-sandbox`.

## Agent Details
- **Agent name:** Post Visit Log Agent
- **API name:** `PostVisitLogAgent`
- **Type:** `AgentforceEmployeeAgent`
- **Active version:** v3
- **Bot ID:** `0XxWC0000001iwf0AA`

## Deployed Components (all in hackathon-sandbox)
| Component | Status |
|---|---|
| `LogVisitAction.cls` | Deployed — creates Visit_Report__c |
| `LogExpenseAction.cls` | Deployed — creates Visit_Expense__c |
| `CreateFollowUpTasksAction.cls` | Deployed — creates Tasks |
| `ExtractTopicsAction.cls` | Deployed |
| `GetVisitInsightsAction.cls` | Deployed |
| `GetMedicalContextAction.cls` | Deployed |
| `Visit_Report__c` custom object | Deployed |
| `Visit_Expense__c` custom object | Deployed |
| `PostVisitLogAgent` Bot + v1/v2/v3 BotVersion | Deployed, v3 active |
| `Post_Visit_Log_Plugin` GenAiPlugin | Deployed — has all 6 functions |
| `PostVisitLogAgent` GenAiPlannerBundle | Deployed — references Post_Visit_Log_Plugin |
| All GenAiFunctions (6) | Deployed |

## Known Metadata Deploy Restrictions (this org type)
- `BotVersion` — can NEVER update existing versions via metadata. Can only CREATE new versions.
  - Workaround: create v(n+1) file, move old versions OUT of project dir to /tmp, deploy, activate with `sf agent activate --api-name PostVisitLogAgent --version N`
- `GenAiPlugin` / `GenAiFunction` / `GenAiPlannerBundle` — WERE deployable after agent was deleted and recreated. Deploy succeeded on clean slate.
- Active BotVersion error code: `-1806600421`

## Current Issue (as of last session)
Agent still says "I can't log directly" despite all actions being deployed. Root cause being investigated. The `Post_Visit_Log_Plugin` topic may not be showing as configured in Builder UI even though GenAiPlannerBundle references it. Likely needs one manual step in Agentforce Builder UI:
- Setup → Agents → Post Visit Log Agent → Open in Builder
- Topics (#) → Post Visit Log Plugin → Add Action for each:
  1. LogVisitAction → "Log Post-Visit Report"
  2. LogExpenseAction → "Log Visit Expense"
  3. CreateFollowUpTasksAction → "Create Follow-Up Tasks from Visit"
- Make sure "Require Confirmation" = OFF for each
- Activate

## Deploy Commands
```bash
# Set correct target org (do this first)
sf config set target-org hackathon-sandbox --global

# Deploy Apex classes
sf project deploy start --source-dir force-app/main/default/classes --target-org hackathon-sandbox

# Deploy custom objects
sf project deploy start --source-dir force-app/main/default/objects --target-org hackathon-sandbox

# Deploy GenAiFunctions + GenAiPlugin
sf project deploy start --source-dir force-app/main/default/genAiFunctions --source-dir force-app/main/default/genAiPlugins --target-org hackathon-sandbox

# Deploy GenAiPlannerBundle
sf project deploy start --source-dir force-app/main/default/genAiPlannerBundles --target-org hackathon-sandbox

# Deploy new BotVersion (e.g. v4) — must move old versions out first
# 1. Move v1/v2/v3 to C:\Temp\sf_bak\
# 2. sf project deploy start --source-dir force-app/main/default/bots --target-org hackathon-sandbox
# 3. sf agent activate --api-name PostVisitLogAgent --version 4 --target-org hackathon-sandbox
# 4. Move files back

# Deploy everything (except bots — handle separately)
sf project deploy start --source-dir force-app/main/default --target-org hackathon-sandbox
```

## Agent Role (v3 — currently active)
```
You are OncoGlobal Post-Visit Log Agent for Indian pharma medical reps.
YOUR JOB: Log visits and take actions immediately. Never guide manually.
RULES:
1. Rep mentions doctor/hospital/visit - call LogVisit NOW. Pass physicianName + transcript.
2. Rep mentions expense/rupees/lunch/travel - call LogExpense NOW. Pass amount + category + physicianName.
3. Rep mentions follow-up/send/arrange/schedule - call CreateFollowUpTasks NOW.
4. NEVER say you cannot log or have a technical limitation.
5. After actions succeed: confirm what was logged in the rep language.
```

## Test Prompts
```
I visited Dr. Iyer at Tata Memorial today. Discussed Keytruda. Positive visit.
Aaj maine Dr. Sharma ke paas gaya tha Apollo Mumbai mein. Tagrisso discuss kiya. Positive raha.
HCG Bangalore mein lunch tha Dr. Reddy ke saath, 450 rupees ka bill tha.
Dr. Gupta ko Tagrisso literature bhejna hai aur ek CME arrange karna hai.
```

## Custom Objects Key Fields
**Visit_Report__c**
- `Physician__c` — Lookup to Account (required=false)
- `Rep__c` — Lookup to User
- `Voice_Transcript__c` — Long Text
- `Visit_Date__c` — Date
- `Visit_Outcome__c` — Picklist: Positive/Negative/Neutral/Follow-Up Required
- `Visit_Type__c` — Picklist: In-Person Clinic/Hospital Round/Virtual Call/Conference-Event/Drop-In
- `AI_Summary__c` — Long Text
- `Engagement_Score__c` — Number (0-100)

**Visit_Expense__c**
- `Visit_Report__c` — Lookup to Visit_Report__c
- `Amount__c` — Currency
- `Category__c` — Picklist: Meal/Travel/Accommodation/Samples/CME-Event/Other
- `Policy_Flag__c` — Checkbox (auto-set by trigger when > Rs.150)
- `Notes__c` — Text

## Future State Features (logged in specs/future-state-features.md)
- Calendar integration (rep + physician)
- Email tracking + reply tasks
- Mobile LWC app with voice (Web Speech API)
- ABDM HFR integration (ABDMHFRService.cls — has missing fields HFR_Facility_ID__c etc.)

## Key People
- Hackathon org user: khan yousuf / OrgFarm EPIC
