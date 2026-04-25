# OncoGlobal Post-Visit Log Agent

An AI-powered Salesforce Agentforce agent for Indian pharma medical representatives. Reps narrate their post-visit summary in natural language (English or Hinglish) and the agent automatically creates visit reports, expense records, and follow-up tasks in Salesforce.

Built for the **Agentforce Hackathon 2026**.

---

## What It Does

A medical rep walks out of a physician's office and says:

> "Aaj maine Dr. Sharma ke paas gaya tha Apollo Mumbai mein. Tagrisso discuss kiya. Positive raha. Lunch tha 450 rupees ka. Dobara jaana hai next week."

The agent:
1. Creates a `Visit_Report__c` record for Dr. Sharma at Apollo Mumbai
2. Logs a `Visit_Expense__c` of Rs. 450 (and flags it — exceeds Rs. 150 policy limit)
3. Creates a follow-up `Task` due in 3 days

No forms. No Salesforce IDs. Under 60 seconds.

---

## Quick Start

### Prerequisites
- Salesforce CLI (`sf`) installed
- Node.js 18+
- Access to the `hackathon-sandbox` org

### Setup
```bash
git clone https://github.com/aryanx455/OncoGlobal-Agentforce.git
cd OncoGlobal-Agentforce

# Authenticate to the hackathon sandbox
sf org login web --alias hackathon-sandbox --instance-url https://test.salesforce.com
sf config set target-org hackathon-sandbox --global

# Verify you're on the right org
sf org display --target-org hackathon-sandbox
# Should show: orgfarm-a5659b3ee2--hackathon.sandbox.my.salesforce.com
```

### Deploy
```bash
# Deploy Apex classes
sf project deploy start --source-dir force-app/main/default/classes --target-org hackathon-sandbox

# Deploy custom objects
sf project deploy start --source-dir force-app/main/default/objects --target-org hackathon-sandbox

# Deploy triggers
sf project deploy start --source-dir force-app/main/default/triggers --target-org hackathon-sandbox
```

> For deploying GenAi metadata (Plugin, Functions, PlannerBundle, BotVersion), see `docs/ARCHITECTURE.md` — these have platform restrictions requiring specific workarounds.

---

## Documentation

| Doc | Purpose |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | LLM context — read automatically by Claude Code. Current status, all deploy commands. |
| [`docs/BRD.md`](docs/BRD.md) | Business requirements — problem statement, objectives, success metrics |
| [`docs/FRD.md`](docs/FRD.md) | Functional requirements — all 6 agent actions, data model, Hinglish support |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Technical architecture — metadata chain, Apex classes, deploy map and gotchas |
| [`docs/AGENT_COLLABORATION.md`](docs/AGENT_COLLABORATION.md) | LLM onboarding guide — current status, what's broken, how to contribute |

**AI contributors:** Start with `CLAUDE.md` then `docs/AGENT_COLLABORATION.md`.

---

## Architecture Overview

```
Rep speaks
    → Agentforce Chat Widget
    → PostVisitLogAgent (Bot v3)
    → GenAiPlannerBundle → Post_Visit_Log_Plugin (Topic)
    → GenAiFunction → @InvocableMethod Apex class
    → Salesforce DML (Visit_Report__c / Visit_Expense__c / Task)
```

6 agent actions:
- **LogVisit** — Creates Visit_Report__c, resolves physician by name
- **LogExpense** — Creates Visit_Expense__c, flags policy violations (>Rs.150)
- **CreateFollowUpTasks** — Creates Task records from natural language commitments
- **ExtractTopics** — Parses drug names and physician reactions from transcript
- **GetVisitInsights** — Returns visit history for a physician
- **GetMedicalContext** — Returns oncology drug and specialty context

---

## Target Org

| Setting | Value |
|---|---|
| Alias | `hackathon-sandbox` |
| URL | `https://orgfarm-a5659b3ee2--hackathon.sandbox.my.salesforce.com` |
| API Version | 66.0 |

> There is also a `d360-sandbox` — this is the **wrong org**. Always use `hackathon-sandbox`.

---

## Current Status

All backend components are deployed. The agent requires one manual step in Agentforce Builder UI to wire the actions to the topic before it will work end-to-end. See `docs/AGENT_COLLABORATION.md` Section 3 for exact steps.

---

## Test Prompts

```
# English
I visited Dr. Iyer at Tata Memorial today. Discussed Keytruda. Positive visit.

# Hinglish visit
Aaj maine Dr. Sharma ke paas gaya tha Apollo Mumbai mein. Tagrisso discuss kiya. Positive raha.

# Expense (flags policy violation)
HCG Bangalore mein lunch tha Dr. Reddy ke saath, 450 rupees ka bill tha.

# Follow-up tasks
Dr. Gupta ko Tagrisso literature bhejna hai aur ek CME arrange karna hai.
```

---

## Tech Stack

- Salesforce Agentforce (AgentforceEmployeeAgent)
- Apex (@InvocableMethod action classes)
- Salesforce CLI (`sf`)
- Custom objects: `Visit_Report__c`, `Visit_Expense__c`
- Language: Hinglish (Hindi-English) supported natively
