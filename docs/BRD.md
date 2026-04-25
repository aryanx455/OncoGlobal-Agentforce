# Business Requirements Document (BRD)
## OncoGlobal Post-Visit Log Agent — Agentforce Hackathon

**Version:** 1.0  
**Date:** April 2026  
**Status:** Active Development

---

## 1. Executive Summary

OncoGlobal is an Indian pharmaceutical company specializing in oncology. Its medical representatives (MRs) visit oncology physicians across India daily to promote cancer treatments. After each visit, reps must log visit details, expenses, and follow-up actions into Salesforce — a process currently done manually and inconsistently.

This project delivers an **AI-powered voice agent** embedded in Salesforce that lets reps narrate their post-visit summary in natural language (English or Hinglish) and automatically creates all required records.

---

## 2. Business Problem

| Problem | Impact |
|---|---|
| Manual visit logging takes 10-15 mins per visit | Lost selling time; reps skip logging |
| Inconsistent data quality across reps | Poor reporting, inaccurate territory insights |
| Expense logging is error-prone | Compliance risk, inaccurate reimbursements |
| Follow-up tasks are forgotten | Lost sales opportunities |
| Reps in the field can't type easily | Adoption barrier for mobile users |

---

## 3. Business Objectives

1. **Reduce post-visit admin time** from 10-15 minutes to under 60 seconds
2. **Increase logging compliance** — every visit gets logged, not just convenient ones
3. **Improve data quality** — AI extracts structured data from natural speech
4. **Enable real-time territory insights** — management sees visit data same day
5. **Automate expense compliance** — flag policy violations automatically (>Rs.150)

---

## 4. Stakeholders

| Role | Interest |
|---|---|
| Medical Representatives (MRs) | Primary users — need fast, easy logging |
| Territory Managers | Need accurate visit data for coaching |
| Finance / Compliance | Need expense data with policy enforcement |
| Medical Affairs | Need discussion topic data (drug feedback) |
| IT / Salesforce Admin | Need maintainable, deployable solution |

---

## 5. Scope

### In Scope (Phase 1 — Hackathon)
- Voice/text post-visit logging via Agentforce chat widget
- Physician visit report creation (Visit_Report__c)
- Expense logging with compliance flagging (Visit_Expense__c)
- Follow-up task creation (Standard Task object)
- Hinglish language support
- Physician name resolution (no Salesforce IDs needed)

### Out of Scope (Phase 1) — See Future State
- Calendar integration
- Email tracking
- Mobile native app
- ABDM HFR registry integration
- Real-time voice streaming

---

## 6. Business Rules

| Rule | Detail |
|---|---|
| Expense policy limit | Rs. 150 per transaction — auto-flagged above this |
| Visit date | Defaults to today; cannot be future |
| Physician lookup | Match by name (fuzzy); create placeholder if not found |
| Task due date | Default 3 days from today |
| Currency | Indian Rupees (Rs.) only |
| Engagement score | 0-100 scale |

---

## 7. Success Metrics

| Metric | Target |
|---|---|
| Visit logging time | < 60 seconds per visit |
| Agent action success rate | > 95% of utterances result in correct action |
| Physician resolution accuracy | > 90% correct match on first attempt |
| Expense policy flag accuracy | 100% (> Rs.150 always flagged) |
| Hinglish comprehension | All key phrases recognized correctly |

---

## 8. Constraints

- Salesforce OrgFarm Hackathon Sandbox (limited metadata deploy support)
- `GenAiPlugin`, `GenAiFunction`, `GenAiPlannerBundle`, `BotVersion` — UI-managed only in this org
- Indian Rupee currency only
- No real-time voice streaming in Phase 1 (text input only in Agentforce widget)
- Expense policy limit hardcoded at Rs.150 (configurable via VisitPolicy__mdt in future)
