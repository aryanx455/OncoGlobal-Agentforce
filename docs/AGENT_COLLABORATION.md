# Agent Collaboration Guide
## OncoGlobal Post-Visit Log Agent — LLM Onboarding

> This document is written for AI assistants (Claude, GPT, Gemini, etc.) picking up this project cold. Read this first, then read `CLAUDE.md` in the repo root for the latest status.

---

## 1. What This Project Is

An **Agentforce (Salesforce AI) agent** that lets Indian pharma medical reps log physician visits by speaking naturally — in English or Hinglish — instead of filling out forms. The agent:
1. Logs the visit (`Visit_Report__c`)
2. Logs any expenses (`Visit_Expense__c`)
3. Creates follow-up tasks (standard Salesforce `Task`)

All via conversational AI — no Salesforce IDs needed from the rep.

**Stack:** Salesforce Agentforce → Apex @InvocableMethod classes → Salesforce data objects.

**Language:** English + Hinglish (Hindi-English mix used by Indian pharma reps).

---

## 2. Read These Files In Order

```
1. CLAUDE.md                    → Current status, target org, quick deploy commands
2. docs/BRD.md                  → Business problem, objectives, constraints
3. docs/FRD.md                  → Functional requirements (all 6 agent actions)
4. docs/ARCHITECTURE.md         → Technical architecture, metadata chain, deploy map
5. force-app/main/default/      → All source code
```

---

## 3. Current Status (as of April 2026)

### What Is Deployed and Working
| Component | Status |
|---|---|
| All 6 Apex action classes | Deployed to `hackathon-sandbox` |
| `Visit_Report__c` custom object | Deployed |
| `Visit_Expense__c` custom object | Deployed |
| `VisitExpenseTrigger` + handler | Deployed |
| `VisitReportTrigger` + handler | Deployed |
| `Post_Visit_Log_Plugin` (GenAiPlugin) | Deployed — has all 6 functions wired |
| `PostVisitLogAgent` GenAiPlannerBundle | Deployed — references the plugin |
| `PostVisitLogAgent` Bot (v1/v2/v3) | Deployed — v3 is ACTIVE |
| GitHub repo | `https://github.com/aryanx455/OncoGlobal-Agentforce` |

### Known Issue — Agent Needs Builder UI Step

**Symptom:** Agent responds with "I can't log directly" or "I have a technical limitation."

**Root cause:** Even with all metadata deployed, Agentforce Builder requires a **manual action-wiring step** that cannot be done via CLI or metadata deploy.

**Fix (manual — requires Salesforce UI access):**
1. Go to `Setup → Agents → Post Visit Log Agent → Open in Builder`
2. Click **Topics** (#) tab → Select **Post Visit Log Plugin**
3. Click **+ New Agent Action** and add each of these:
   - `LogVisitAction` → Label: "Log Post-Visit Report"
   - `LogExpenseAction` → Label: "Log Visit Expense"
   - `CreateFollowUpTasksAction` → Label: "Create Follow-Up Tasks from Visit"
4. For each action: set **Require Confirmation = OFF**
5. Click **Activate**

> This is the #1 outstanding task. Without it, the agent cannot call any Apex actions.

---

## 4. Project Structure

```
force-app/main/default/
├── bots/PostVisitLogAgent/
│   ├── PostVisitLogAgent.bot-meta.xml        # Bot definition
│   ├── v1.botVersion-meta.xml                # Old version
│   ├── v2.botVersion-meta.xml                # Old version
│   └── v3.botVersion-meta.xml                # ACTIVE — has planner reference + role
├── classes/
│   ├── LogVisitAction.cls                    # FR-001: Creates Visit_Report__c
│   ├── LogExpenseAction.cls                  # FR-002: Creates Visit_Expense__c
│   ├── CreateFollowUpTasksAction.cls         # FR-003: Creates Tasks
│   ├── ExtractTopicsAction.cls               # FR-004: Parses discussion topics
│   ├── GetVisitInsightsAction.cls            # FR-005: Returns visit history
│   ├── GetMedicalContextAction.cls           # FR-006: Returns drug/specialty context
│   ├── VisitExpenseTriggerHandler.cls        # Policy flagging logic
│   └── VisitReportTriggerHandler.cls         # Account rollup logic
├── genAiFunctions/                           # 6 GenAiFunction definitions
├── genAiPlugins/Post_Visit_Log_Plugin/       # Topic definition + function references
├── genAiPlannerBundles/PostVisitLogAgent/    # Planner → Plugin wiring
├── objects/                                  # Custom object field definitions
├── triggers/                                 # VisitExpense + VisitReport triggers
└── permissionsets/OncoGlobal_Access.permissionset-meta.xml
```

---

## 5. Target Org

| Setting | Value |
|---|---|
| Alias | `hackathon-sandbox` |
| Instance URL | `https://orgfarm-a5659b3ee2--hackathon.sandbox.my.salesforce.com` |
| Login URL (for auth) | `https://test.salesforce.com` |

**WARNING:** There is also a `d360-sandbox` org (`yousuf61-dev-ed.my.salesforce.com`). This is the WRONG org. Never deploy there.

### Setting Up Auth (on a new machine)
```bash
sf org login web --alias hackathon-sandbox --instance-url https://test.salesforce.com
sf config set target-org hackathon-sandbox --global
sf org display --target-org hackathon-sandbox  # verify correct org
```

---

## 6. Deploy Commands

```bash
# Verify you're targeting the right org first
sf org display --target-org hackathon-sandbox

# Deploy Apex classes
sf project deploy start --source-dir force-app/main/default/classes --target-org hackathon-sandbox

# Deploy custom objects
sf project deploy start --source-dir force-app/main/default/objects --target-org hackathon-sandbox

# Deploy triggers
sf project deploy start --source-dir force-app/main/default/triggers --target-org hackathon-sandbox

# Deploy GenAi metadata (only works on clean slate — see Architecture doc)
sf project deploy start --source-dir force-app/main/default/genAiFunctions --target-org hackathon-sandbox
sf project deploy start --source-dir force-app/main/default/genAiPlugins --target-org hackathon-sandbox
sf project deploy start --source-dir force-app/main/default/genAiPlannerBundles --target-org hackathon-sandbox

# Deploy bot (see Architecture doc for BotVersion deploy workaround)
# DO NOT run this without reading Section 5 of ARCHITECTURE.md first
```

---

## 7. Metadata Deploy Gotchas

These are hard-won lessons. Read before touching deploy.

### BotVersion — NEVER update existing, always create new
- Existing BotVersions throw error `-1806600421` on any update attempt
- Workaround: create `vN.botVersion-meta.xml`, move ALL OTHER version files to a temp dir OUTSIDE the project (not just rename), deploy, activate with `sf agent activate --api-name PostVisitLogAgent --version N`, then restore files

### GenAiPlugin / GenAiFunction / GenAiPlannerBundle
- "Not available for deploy" if they already exist in the org
- Only deployable on a completely clean slate (after deleting the agent from Setup)
- After deletion + redeploy, these land in the org but action wiring must still be done in Builder UI

### rollbackOnError: true (default)
- Any single failed component in a deploy rolls back the entire transaction
- This means a bad `.bak` file in the bots dir will silently undo your Apex deploy too
- Always move bad/old files completely OUTSIDE the project directory

### HTML entities in role text
- `<role>` field in `botVersion-meta.xml` must contain plain ASCII only
- Em dashes (`—`), arrows (`→`), and smart quotes cause XML parse errors
- Use plain hyphen `-` and `->` instead

---

## 8. Test the Agent

Once deployed and Builder UI wiring is done:

1. Open `https://orgfarm-a5659b3ee2--hackathon.sandbox.my.salesforce.com`
2. Click the Agentforce chat widget (bottom right)
3. Use these test prompts:

```
# English
I visited Dr. Iyer at Tata Memorial today. Discussed Keytruda. Positive visit.

# Hinglish
Aaj maine Dr. Sharma ke paas gaya tha Apollo Mumbai mein. Tagrisso discuss kiya. Positive raha.

# Expense
HCG Bangalore mein lunch tha Dr. Reddy ke saath, 450 rupees ka bill tha.

# Follow-up tasks
Dr. Gupta ko Tagrisso literature bhejna hai aur ek CME arrange karna hai.
```

**Expected behavior:**
- Agent calls LogVisit and returns Visit Report ID
- Agent calls LogExpense and notes Rs.450 exceeds Rs.150 policy limit
- Agent creates 2 Tasks and confirms in Hinglish

---

## 9. Where to Contribute

### High Priority
1. **Fix the agent** — Complete the Builder UI action wiring step (Section 3)
2. **Add test coverage** — `*Test.cls` files in `/classes/` are minimal; expand them
3. **Run agent test spec** — `specs/PostVisitLogAgent-testSpec.yaml` defines test cases

### Medium Priority
4. **Custom metadata for policy limit** — `VisitExpenseTriggerHandler` has Rs.150 hardcoded; move to `VisitPolicy__mdt`
5. **Physician resolution improvements** — `LogVisitAction.resolvePhysician()` uses wildcards; add fuzzy matching

### Low Priority / Phase 2
6. See `specs/future-state-features.md` for Calendar integration, Mobile LWC, ABDM HFR registry, etc.

---

## 10. Hinglish Reference

| Hinglish phrase | English meaning |
|---|---|
| `gaya tha` | visited |
| `baat ki` | discussed |
| `positive raha` | positive outcome |
| `negative gaya` | negative outcome |
| `rupees ka bill tha` | expense amount |
| `bhejna hai` | need to send (follow-up) |
| `arrange karna hai` | need to arrange |
| `dobara jaana hai` | need to revisit |
| `follow up banana hai` | create follow-up |
| `samples diye` | gave samples |
| `[Drug] ke baare mein baat ki` | discussed [Drug] |

---

## 11. Key Salesforce Concepts (for non-SF LLMs)

- **Agentforce**: Salesforce's AI agent platform. Agents are configured in a Builder UI and powered by a large language model.
- **GenAiFunction**: Exposes an Apex `@InvocableMethod` to the Agentforce agent as a callable tool.
- **GenAiPlugin**: Groups related GenAiFunctions into a "Topic" (e.g., "Visit Logging").
- **GenAiPlannerBundle**: Wires a set of Topics/Plugins to a specific Bot version.
- **BotVersion**: A versioned configuration of the agent (role, dialogs, planner reference). Only new versions can be created via CLI.
- **@InvocableMethod**: Apex annotation that makes a static method callable from flows, bots, and Agentforce.
- **without sharing**: Apex keyword meaning the code bypasses record-level sharing rules (used here so the agent can always access relevant data as the calling user).

---

*Last updated: April 2026 | Active org: hackathon-sandbox | Active version: v3*
