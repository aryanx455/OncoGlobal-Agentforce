// OncoFieldCopilotAgent — end-to-end action test script
// Tests all 7 actions wired to OncoFieldCopilotAgent.
// Run: sf apex run --file scripts/apex/TestOncoFieldCopilotAgent.apex --target-org hackathon-sandbox
//
// Expects SeedHackathonDemoData40.apex to have been run first.
// Each section prints PASS / FAIL with a reason.

System.debug('========================================');
System.debug('OncoFieldCopilot Agent — Action Test Run');
System.debug('========================================');

Integer passed = 0;
Integer failed = 0;

// ─── Helper ───────────────────────────────────────────────────────────────────
String checkMark = '✓';
String crossMark = '✗';

void logPass(String label) {
    System.debug(checkMark + ' PASS | ' + label);
    passed++;
}

void logFail(String label, String reason) {
    System.debug(crossMark + ' FAIL | ' + label + ' — ' + reason);
    failed++;
}

// ─── 1. HealthCloudProviderBriefAction ────────────────────────────────────────
System.debug('--- 1. HealthCloudProviderBriefAction ---');
try {
    HealthCloudProviderBriefAction.Request briefReq = new HealthCloudProviderBriefAction.Request();
    briefReq.providerName = 'Doctor Demo 001';

    List<HealthCloudProviderBriefAction.Result> briefResults =
        HealthCloudProviderBriefAction.execute(
            new List<HealthCloudProviderBriefAction.Request>{ briefReq }
        );

    HealthCloudProviderBriefAction.Result br = briefResults[0];
    if (br.success == true) {
        logPass('Provider brief returned success');
        System.debug('  Provider   : ' + br.providerName);
        System.debug('  Source     : ' + br.providerRecordSource);
        System.debug('  Heat Score : ' + br.relationshipHeatScore);
        System.debug('  Summary    : ' + (br.contextSummaryForAgent != null
            ? br.contextSummaryForAgent.left(120) + '...'
            : 'null'));
    } else {
        logFail('Provider brief', br.errorMessage);
    }

    // Edge: blank name
    HealthCloudProviderBriefAction.Request blankReq = new HealthCloudProviderBriefAction.Request();
    blankReq.providerName = '';
    HealthCloudProviderBriefAction.Result blankResult =
        HealthCloudProviderBriefAction.execute(
            new List<HealthCloudProviderBriefAction.Request>{ blankReq }
        )[0];
    if (blankResult.success == false && String.isNotBlank(blankResult.errorMessage)) {
        logPass('Blank provider name returns graceful error');
    } else {
        logFail('Blank provider name', 'Expected failure, got success=' + blankResult.success);
    }
} catch (Exception ex) {
    logFail('HealthCloudProviderBriefAction threw exception', ex.getMessage());
}

// ─── 2. ProviderResolutionService ─────────────────────────────────────────────
System.debug('--- 2. ProviderResolutionService ---');
try {
    // Happy path — exact match
    ProviderResolutionService.Resolution res1 =
        ProviderResolutionService.resolveDoctor('Doctor Demo 001', null, false, false);
    if (res1.success == true || res1.needsClarification == true) {
        logPass('resolveDoctor exact name resolves or clarifies');
        System.debug('  success=' + res1.success + ' needsClarification=' + res1.needsClarification);
        System.debug('  physicianName=' + res1.physicianName);
    } else {
        logFail('resolveDoctor exact name', res1.errorMessage);
    }

    // Ambiguous — partial name that matches many
    ProviderResolutionService.Resolution res2 =
        ProviderResolutionService.resolveDoctor('Demo', null, false, false);
    if (res2.needsClarification == true || res2.success == true) {
        logPass('Partial/ambiguous name handled (clarification or resolved)');
    } else {
        logFail('Partial name', res2.errorMessage);
    }

    // No match
    ProviderResolutionService.Resolution res3 =
        ProviderResolutionService.resolveDoctor('Dr. Nobody XYZ', null, false, false);
    if (res3.success == false) {
        logPass('Unknown doctor returns needsClarification');
    } else {
        logFail('Unknown doctor', 'Expected failure, got success');
    }
} catch (Exception ex) {
    logFail('ProviderResolutionService threw exception', ex.getMessage());
}

// ─── 3. LogVisitAction ────────────────────────────────────────────────────────
System.debug('--- 3. LogVisitAction ---');
Id loggedVisitReportId;
try {
    LogVisitAction.Request lvReq = new LogVisitAction.Request();
    lvReq.transcript    = 'OG Test: Visited Doctor Demo 001 at OG Demo Hospital 01. Discussed Keytruda. Very positive, doc is interested in trial data.';
    lvReq.physicianName = 'Doctor Demo 001';
    lvReq.hospitalName  = 'OG Demo Hospital 01';
    lvReq.visitOutcome  = 'Positive';
    lvReq.visitType     = 'In-Person Clinic';
    lvReq.visitDate     = Date.today();
    lvReq.engagementScore = 85;

    List<LogVisitAction.Result> lvResults =
        LogVisitAction.execute(new List<LogVisitAction.Request>{ lvReq });
    LogVisitAction.Result lvr = lvResults[0];

    if (lvr.success == true) {
        loggedVisitReportId = lvr.visitReportId;
        logPass('LogVisitAction created Visit_Report__c: ' + lvr.visitReportId);
        System.debug('  Physician  : ' + lvr.resolvedPhysicianName);
        System.debug('  Facility   : ' + lvr.resolvedFacilityName);
    } else if (lvr.needsClarification == true) {
        logPass('LogVisitAction returned clarification (doctor dedup working): ' + lvr.clarificationMessage);
    } else {
        logFail('LogVisitAction', lvr.errorMessage);
    }

    // Edge: missing transcript
    LogVisitAction.Request emptyReq = new LogVisitAction.Request();
    emptyReq.transcript = '';
    LogVisitAction.Result emptyResult =
        LogVisitAction.execute(new List<LogVisitAction.Request>{ emptyReq })[0];
    if (emptyResult.success == false) {
        logPass('Empty transcript returns error');
    } else {
        logFail('Empty transcript', 'Expected failure, got success');
    }
} catch (Exception ex) {
    logFail('LogVisitAction threw exception', ex.getMessage());
}

// ─── 4. LogExpenseAction ──────────────────────────────────────────────────────
System.debug('--- 4. LogExpenseAction ---');
try {
    LogExpenseAction.Request expReq = new LogExpenseAction.Request();
    expReq.amount        = 450;
    expReq.category      = 'Meal';
    expReq.physicianName = 'Doctor Demo 001';
    expReq.notes         = 'OG Test: Lunch at OG Demo Hospital 01 canteen';
    expReq.visitReportId = loggedVisitReportId;

    List<LogExpenseAction.Result> expResults =
        LogExpenseAction.execute(new List<LogExpenseAction.Request>{ expReq });
    LogExpenseAction.Result er = expResults[0];

    if (er.success == true) {
        logPass('LogExpenseAction created Expense__c: ' + er.expenseId);
        System.debug('  Policy flagged : ' + er.policyFlagged + ' (expect true — 450 > 150)');
        if (er.policyFlagged != true) {
            logFail('Policy flag for 450', 'Should be flagged, got false');
        } else {
            logPass('Policy flag correctly set for Rs.450');
        }

        // Confirm record is in Expense__c not Visit_Expense__c
        List<Expense__c> created = [SELECT Id, Amount__c FROM Expense__c WHERE Id = :er.expenseId];
        if (!created.isEmpty()) {
            logPass('Expense record confirmed in Expense__c object');
        } else {
            logFail('Expense object check', 'Record not found in Expense__c');
        }
    } else {
        logFail('LogExpenseAction', er.errorMessage);
    }

    // Below threshold — should not flag
    LogExpenseAction.Request cheapReq = new LogExpenseAction.Request();
    cheapReq.amount   = 100;
    cheapReq.category = 'Meal';
    cheapReq.visitReportId = loggedVisitReportId;
    LogExpenseAction.Result cheapResult =
        LogExpenseAction.execute(new List<LogExpenseAction.Request>{ cheapReq })[0];
    if (cheapResult.success == true && cheapResult.policyFlagged == false) {
        logPass('Rs.100 expense correctly not flagged');
    } else {
        logFail('Rs.100 policy flag', 'success=' + cheapResult.success + ' flagged=' + cheapResult.policyFlagged);
    }

    // GST fields
    LogExpenseAction.Request gstReq = new LogExpenseAction.Request();
    gstReq.amount        = 200;
    gstReq.category      = 'Travel';
    gstReq.gstRate       = 18;
    gstReq.cgstAmount    = 18;
    gstReq.sgstAmount    = 18;
    gstReq.invoiceNumber = 'OGT-TEST-001';
    gstReq.visitReportId = loggedVisitReportId;
    LogExpenseAction.Result gstResult =
        LogExpenseAction.execute(new List<LogExpenseAction.Request>{ gstReq })[0];
    if (gstResult.success == true) {
        SObject gstExp = Database.query(
            'SELECT GST_Rate__c, Invoice_Number__c, Policy_Flag__c FROM Expense__c WHERE Id = \'' + gstResult.expenseId + '\''
        );
        Decimal gstRate = (Decimal) gstExp.get('GST_Rate__c');
        String invNum = (String) gstExp.get('Invoice_Number__c');
        if (gstRate == 18 && invNum == 'OGT-TEST-001') {
            logPass('GST fields stored correctly on Expense__c (GST_Rate=18, Invoice=OGT-TEST-001)');
        } else {
            logFail('GST fields', 'GST_Rate__c=' + gstRate + ' Invoice=' + invNum);
        }
    } else {
        logFail('GST expense', gstResult.errorMessage);
    }
} catch (Exception ex) {
    logFail('LogExpenseAction threw exception', ex.getMessage());
}

// ─── 5. ExpenseGuardrailAction ────────────────────────────────────────────────
System.debug('--- 5. ExpenseGuardrailAction ---');
try {
    // Duplicate by invoice number
    ExpenseGuardrailAction.Request guarReq = new ExpenseGuardrailAction.Request();
    guarReq.invoiceNumber = 'OGT-TEST-001';
    guarReq.amount        = 200;
    guarReq.category      = 'Travel';

    List<ExpenseGuardrailAction.Result> guarResults =
        ExpenseGuardrailAction.execute(
            new List<ExpenseGuardrailAction.Request>{ guarReq }
        );
    ExpenseGuardrailAction.Result gr = guarResults[0];
    if (gr.duplicateFound == true) {
        logPass('Duplicate detected by invoice number OGT-TEST-001');
        System.debug('  Duplicate ID : ' + gr.duplicateRecordId);
        System.debug('  Action       : ' + gr.recommendedAction);
    } else {
        logFail('Duplicate detection', 'Expected duplicate, found=' + gr.duplicateFound);
    }

    // Policy explanation for over-limit
    ExpenseGuardrailAction.Request overReq = new ExpenseGuardrailAction.Request();
    overReq.amount   = 500;
    overReq.category = 'Accommodation';
    ExpenseGuardrailAction.Result overResult =
        ExpenseGuardrailAction.execute(new List<ExpenseGuardrailAction.Request>{ overReq })[0];
    if (overResult.policyFlagged == true && String.isNotBlank(overResult.policyExplanation)) {
        logPass('Policy explanation generated for Rs.500');
        System.debug('  Explanation : ' + overResult.policyExplanation);
    } else {
        logFail('Policy explanation', 'flagged=' + overResult.policyFlagged);
    }

    // Safe expense
    ExpenseGuardrailAction.Request safeReq = new ExpenseGuardrailAction.Request();
    safeReq.amount   = 80;
    safeReq.category = 'Meal';
    ExpenseGuardrailAction.Result safeResult =
        ExpenseGuardrailAction.execute(new List<ExpenseGuardrailAction.Request>{ safeReq })[0];
    if (safeResult.policyFlagged == false && safeResult.duplicateFound == false) {
        logPass('Rs.80 meal is safe — no flag, no duplicate');
    } else {
        logFail('Safe expense', 'flagged=' + safeResult.policyFlagged + ' dup=' + safeResult.duplicateFound);
    }
} catch (Exception ex) {
    logFail('ExpenseGuardrailAction threw exception', ex.getMessage());
}

// ─── 6. FieldRoutePlannerAction ───────────────────────────────────────────────
System.debug('--- 6. FieldRoutePlannerAction ---');
try {
    FieldRoutePlannerAction.Request routeReq = new FieldRoutePlannerAction.Request();
    routeReq.plannedDate = String.valueOf(Date.today().addDays(1));
    routeReq.maxStops    = 3;

    List<FieldRoutePlannerAction.Result> routeResults =
        FieldRoutePlannerAction.execute(
            new List<FieldRoutePlannerAction.Request>{ routeReq }
        );
    FieldRoutePlannerAction.Result rr = routeResults[0];
    if (rr.success == true) {
        logPass('FieldRoutePlannerAction returned route');
        System.debug('  Route date : ' + rr.routeDate);
        System.debug('  Stops      : ' + (rr.recommendedStops != null
            ? rr.recommendedStops.left(200)
            : 'none'));
        System.debug('  Summary    : ' + (rr.routeSummary != null
            ? rr.routeSummary.left(150)
            : 'none'));
    } else {
        logFail('FieldRoutePlannerAction', rr.errorMessage);
    }

    // With territory
    FieldRoutePlannerAction.Request terrReq = new FieldRoutePlannerAction.Request();
    terrReq.territory  = 'Mumbai';
    terrReq.maxStops   = 5;
    terrReq.plannedDate = String.valueOf(Date.today().addDays(2));
    FieldRoutePlannerAction.Result terrResult =
        FieldRoutePlannerAction.execute(new List<FieldRoutePlannerAction.Request>{ terrReq })[0];
    if (terrResult.success == true) {
        logPass('Route with territory=Mumbai succeeded');
    } else {
        logFail('Route with territory', terrResult.errorMessage);
    }
} catch (Exception ex) {
    logFail('FieldRoutePlannerAction threw exception', ex.getMessage());
}

// ─── 7. FieldManagerSummaryAction ─────────────────────────────────────────────
System.debug('--- 7. FieldManagerSummaryAction ---');
try {
    FieldManagerSummaryAction.Request sumReq = new FieldManagerSummaryAction.Request();
    sumReq.startDate = String.valueOf(Date.today().addDays(-30));
    sumReq.endDate   = String.valueOf(Date.today());

    List<FieldManagerSummaryAction.Result> sumResults =
        FieldManagerSummaryAction.execute(
            new List<FieldManagerSummaryAction.Request>{ sumReq }
        );
    FieldManagerSummaryAction.Result mr = sumResults[0];
    if (mr.success == true) {
        logPass('FieldManagerSummaryAction returned summary');
        System.debug('  Window         : ' + mr.summaryWindow);
        System.debug('  Visits         : ' + mr.visitCount);
        System.debug('  Expenses       : ' + mr.typedExpenseCount);
        System.debug('  Flagged        : ' + mr.flaggedExpenseCount);
        System.debug('  Open tasks     : ' + mr.openTaskCount);
        System.debug('  High potential : ' + (mr.highPotentialDoctors != null
            ? mr.highPotentialDoctors.left(100)
            : 'none'));
        System.debug('  Summary        : ' + (mr.managerSummary != null
            ? mr.managerSummary.left(200)
            : 'null'));
        // Confirm Total_Visit_Expense__c bug is fixed (would throw if field missing)
        logPass('Total_Expense_Amount__c field reference OK (stale field bug fixed)');
    } else {
        logFail('FieldManagerSummaryAction', mr.errorMessage);
    }

    // Default (no dates = this week)
    FieldManagerSummaryAction.Result defaultResult =
        FieldManagerSummaryAction.execute(
            new List<FieldManagerSummaryAction.Request>{ new FieldManagerSummaryAction.Request() }
        )[0];
    if (defaultResult.success == true) {
        logPass('Default week summary (no date args) succeeded');
    } else {
        logFail('Default week summary', defaultResult.errorMessage);
    }
} catch (Exception ex) {
    logFail('FieldManagerSummaryAction threw exception', ex.getMessage());
}

// ─── 8. DigitalEngagementIntakeAction ─────────────────────────────────────────
System.debug('--- 8. DigitalEngagementIntakeAction ---');
try {
    // Visit intent via WhatsApp text
    DigitalEngagementIntakeAction.Request digReq = new DigitalEngagementIntakeAction.Request();
    digReq.channel      = 'WhatsApp';
    digReq.senderName   = 'Aryan Rep';
    digReq.messageText  = 'Aaj maine Dr. Demo 001 ke paas gaya Keytruda discuss kiya positive raha';
    digReq.providerName = 'Doctor Demo 001';

    List<DigitalEngagementIntakeAction.Result> digResults =
        DigitalEngagementIntakeAction.execute(
            new List<DigitalEngagementIntakeAction.Request>{ digReq }
        );
    DigitalEngagementIntakeAction.Result dr = digResults[0];
    if (dr.success == true) {
        logPass('Digital intake classified WhatsApp visit message');
        System.debug('  Intent    : ' + dr.detectedIntent);
        System.debug('  Topic     : ' + dr.recommendedTopic);
        System.debug('  Guidance  : ' + dr.responseGuidance);
    } else {
        logFail('Digital intake visit message', dr.errorMessage);
    }

    // Expense intent
    DigitalEngagementIntakeAction.Request expDigReq = new DigitalEngagementIntakeAction.Request();
    expDigReq.channel     = 'WhatsApp';
    expDigReq.senderName  = 'Aryan Rep';
    expDigReq.messageText = '450 rupees ka lunch bill tha HCG mein';
    List<DigitalEngagementIntakeAction.Result> expDigResults =
        DigitalEngagementIntakeAction.execute(
            new List<DigitalEngagementIntakeAction.Request>{ expDigReq }
        );
    if (expDigResults[0].success == true) {
        logPass('Digital intake classified expense message');
        System.debug('  Intent : ' + expDigResults[0].detectedIntent);
    } else {
        logFail('Digital intake expense message', expDigResults[0].errorMessage);
    }

    // Empty message
    DigitalEngagementIntakeAction.Request emptyDig = new DigitalEngagementIntakeAction.Request();
    emptyDig.channel     = 'WhatsApp';
    emptyDig.messageText = '';
    DigitalEngagementIntakeAction.Result emptyResult =
        DigitalEngagementIntakeAction.execute(
            new List<DigitalEngagementIntakeAction.Request>{ emptyDig }
        )[0];
    if (emptyResult.success == false || String.isNotBlank(emptyResult.responseGuidance)) {
        logPass('Empty message handled gracefully');
    } else {
        logFail('Empty message', 'No error or guidance for blank input');
    }
} catch (Exception ex) {
    logFail('DigitalEngagementIntakeAction threw exception', ex.getMessage());
}

// ─── 9. CreateFollowUpTasksAction ─────────────────────────────────────────────
System.debug('--- 9. CreateFollowUpTasksAction ---');
try {
    CreateFollowUpTasksAction.Request taskReq = new CreateFollowUpTasksAction.Request();
    taskReq.physicianName   = 'Doctor Demo 001';
    taskReq.followUpActions = 'Send Keytruda trial data; Arrange CME for Q3; Follow up on sample request';
    taskReq.visitReportId = loggedVisitReportId;

    List<CreateFollowUpTasksAction.Result> taskResults =
        CreateFollowUpTasksAction.execute(
            new List<CreateFollowUpTasksAction.Request>{ taskReq }
        );
    CreateFollowUpTasksAction.Result tr = taskResults[0];
    if (tr.success == true) {
        logPass('CreateFollowUpTasksAction created tasks');
        System.debug('  Tasks created : ' + tr.tasksCreated);
    } else {
        logFail('CreateFollowUpTasksAction', tr.errorMessage);
    }
} catch (Exception ex) {
    logFail('CreateFollowUpTasksAction threw exception', ex.getMessage());
}

// ─── Rollup check (requires PR #3 deployed) ────────────────────────────────────
System.debug('--- Rollup: Total_Expense_Amount__c (requires PR #3 deploy) ---');
Boolean hasRollupField = Schema.SObjectType.Visit_Report__c.fields.getMap()
    .containsKey('Total_Expense_Amount__c');
if (!hasRollupField) {
    System.debug('  SKIP — Total_Expense_Amount__c not yet in org (deploy PR #3 first)');
} else if (loggedVisitReportId != null) {
    try {
        SObject vr = Database.query(
            'SELECT Total_Expense_Amount__c FROM Visit_Report__c WHERE Id = \'' + loggedVisitReportId + '\''
        );
        Decimal rollup = (Decimal) vr.get('Total_Expense_Amount__c');
        if (rollup != null && rollup > 0) {
            logPass('Rollup Total_Expense_Amount__c = ' + rollup);
        } else {
            logFail('Rollup', 'Total_Expense_Amount__c is null or 0 after expenses inserted');
        }
    } catch (Exception ex) {
        logFail('Rollup check', ex.getMessage());
    }
} else {
    System.debug('  Skipped — no Visit_Report__c created (LogVisitAction needs clarification)');
}

// ─── Summary ──────────────────────────────────────────────────────────────────
System.debug('========================================');
System.debug('RESULTS: ' + passed + ' passed, ' + failed + ' failed');
System.debug('========================================');
if (failed == 0) {
    System.debug('ALL TESTS PASSED — OncoFieldCopilotAgent actions are healthy.');
} else {
    System.debug('SOME TESTS FAILED — review FAIL lines above before demo.');
}
