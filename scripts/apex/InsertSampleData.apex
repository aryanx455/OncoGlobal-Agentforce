// ============================================================
// OncoGlobal — Sample Data Script
// Run via: sf apex run --file scripts/apex/InsertSampleData.apex --target-org <alias>
// Or paste into Developer Console > Execute Anonymous
// ============================================================

Id currentUserId = UserInfo.getUserId();

// ── 1. HEALTHCARE FACILITY ACCOUNTS ────────────────────────────────────────
Id facilityRTId = Schema.SObjectType.Account
    .getRecordTypeInfosByDeveloperName().get('Healthcare_Facility').getRecordTypeId();

List<Account> facilities = new List<Account>{
    new Account(
        RecordTypeId       = facilityRTId,
        Name               = 'Apollo Cancer Centre',
        Facility_Type__c   = 'Hospital',
        Specialty__c       = 'Oncology',
        Territory__c       = 'Mumbai South',
        Phone              = '+91-22-6760-6666',
        Annual_Patient_Volume__c = 1200,
        Key_Account__c     = true,
        BillingCity        = 'Mumbai',
        BillingState       = 'Maharashtra',
        BillingCountry     = 'India'
    ),
    new Account(
        RecordTypeId       = facilityRTId,
        Name               = 'Tata Memorial Hospital',
        Facility_Type__c   = 'Cancer Centre',
        Specialty__c       = 'Surgical Oncology',
        Territory__c       = 'Mumbai Central',
        Phone              = '+91-22-2417-7000',
        Annual_Patient_Volume__c = 2500,
        Key_Account__c     = true,
        BillingCity        = 'Mumbai',
        BillingState       = 'Maharashtra',
        BillingCountry     = 'India'
    ),
    new Account(
        RecordTypeId       = facilityRTId,
        Name               = 'HCG Oncology Centre Bangalore',
        Facility_Type__c   = 'Hospital',
        Specialty__c       = 'Radiation Oncology',
        Territory__c       = 'Bangalore North',
        Phone              = '+91-80-4020-0200',
        Annual_Patient_Volume__c = 900,
        Key_Account__c     = false,
        BillingCity        = 'Bangalore',
        BillingState       = 'Karnataka',
        BillingCountry     = 'India'
    )
};
insert facilities;
System.debug('Inserted ' + facilities.size() + ' facilities');

// ── 2. PHYSICIAN ACCOUNTS ────────────────────────────────────────────────────
Id physicianRTId = Schema.SObjectType.Account
    .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();

List<Account> physicians = new List<Account>{
    new Account(
        RecordTypeId         = physicianRTId,
        Name                 = 'Dr. Priya Sharma',
        Specialty__c         = 'Oncology',
        NPI__c               = '1234567890',
        Territory__c         = 'Mumbai South',
        ParentId             = facilities[0].Id,
        Phone                = '+91-98200-11111',
        Preferred_Visit_Day__c  = 'Tuesday',
        Preferred_Visit_Time__c = 'Morning (9am–12pm)',
        Key_Account__c       = true
    ),
    new Account(
        RecordTypeId         = physicianRTId,
        Name                 = 'Dr. Rakesh Gupta',
        Specialty__c         = 'Surgical Oncology',
        NPI__c               = '2345678901',
        Territory__c         = 'Mumbai Central',
        ParentId             = facilities[1].Id,
        Phone                = '+91-98200-22222',
        Preferred_Visit_Day__c  = 'Wednesday',
        Preferred_Visit_Time__c = 'Afternoon (1pm–4pm)',
        Key_Account__c       = true
    ),
    new Account(
        RecordTypeId         = physicianRTId,
        Name                 = 'Dr. Anita Desai',
        Specialty__c         = 'Haematology',
        NPI__c               = '3456789012',
        Territory__c         = 'Mumbai South',
        ParentId             = facilities[0].Id,
        Phone                = '+91-98200-33333',
        Preferred_Visit_Day__c  = 'Thursday',
        Preferred_Visit_Time__c = 'Morning (9am–12pm)',
        Key_Account__c       = false
    ),
    new Account(
        RecordTypeId         = physicianRTId,
        Name                 = 'Dr. Suresh Nair',
        Specialty__c         = 'Radiation Oncology',
        NPI__c               = '4567890123',
        Territory__c         = 'Bangalore North',
        ParentId             = facilities[2].Id,
        Phone                = '+91-98200-44444',
        Preferred_Visit_Day__c  = 'Monday',
        Preferred_Visit_Time__c = 'Morning (9am–12pm)',
        Key_Account__c       = false
    ),
    new Account(
        RecordTypeId         = physicianRTId,
        Name                 = 'Dr. Meena Iyer',
        Specialty__c         = 'Pathology',
        NPI__c               = '5678901234',
        Territory__c         = 'Mumbai Central',
        ParentId             = facilities[1].Id,
        Phone                = '+91-98200-55555',
        Preferred_Visit_Day__c  = 'Friday',
        Preferred_Visit_Time__c = 'Afternoon (1pm–4pm)',
        Key_Account__c       = false
    )
};
insert physicians;
System.debug('Inserted ' + physicians.size() + ' physicians');

// ── 3. CONTACTS (linked to physician accounts) ───────────────────────────────
List<Contact> contacts = new List<Contact>{
    new Contact(
        FirstName   = 'Priya',
        LastName    = 'Sharma',
        AccountId   = physicians[0].Id,
        Title       = 'Senior Oncologist',
        Department  = 'Medical Oncology',
        Phone       = '+91-98200-11111',
        Email       = 'priya.sharma@apollocancer.in'
    ),
    new Contact(
        FirstName   = 'Rakesh',
        LastName    = 'Gupta',
        AccountId   = physicians[1].Id,
        Title       = 'Head of Surgical Oncology',
        Department  = 'Surgical Oncology',
        Phone       = '+91-98200-22222',
        Email       = 'rakesh.gupta@tatamemorial.in'
    ),
    new Contact(
        FirstName   = 'Anita',
        LastName    = 'Desai',
        AccountId   = physicians[2].Id,
        Title       = 'Haematologist',
        Department  = 'Haematology',
        Phone       = '+91-98200-33333',
        Email       = 'anita.desai@apollocancer.in'
    ),
    new Contact(
        FirstName   = 'Suresh',
        LastName    = 'Nair',
        AccountId   = physicians[3].Id,
        Title       = 'Radiation Oncologist',
        Department  = 'Radiation',
        Phone       = '+91-98200-44444',
        Email       = 'suresh.nair@hcgbangalore.in'
    ),
    new Contact(
        FirstName   = 'Meena',
        LastName    = 'Iyer',
        AccountId   = physicians[4].Id,
        Title       = 'Pathologist',
        Department  = 'Pathology',
        Phone       = '+91-98200-55555',
        Email       = 'meena.iyer@tatamemorial.in'
    )
};
insert contacts;
System.debug('Inserted ' + contacts.size() + ' contacts');

// ── 4. VISIT REPORTS ─────────────────────────────────────────────────────────
List<Visit_Report__c> visits = new List<Visit_Report__c>{
    new Visit_Report__c(
        Physician__c       = physicians[0].Id,
        Rep__c             = currentUserId,
        Visit_Date__c      = Date.today().addDays(-14),
        Visit_Outcome__c   = 'Positive',
        Engagement_Score__c = 85,
        Discussion_Topics__c = 'Discussed new Keytruda efficacy data in NSCLC; reviewed patient case studies.',
        Follow_Up_Actions__c = 'Send latest clinical trial summary by Friday.',
        AI_Summary__c      = 'High-value visit. Dr. Sharma receptive to new NSCLC data. Requested clinical trial details.'
    ),
    new Visit_Report__c(
        Physician__c       = physicians[1].Id,
        Rep__c             = currentUserId,
        Visit_Date__c      = Date.today().addDays(-10),
        Visit_Outcome__c   = 'Follow-Up Required',
        Engagement_Score__c = 62,
        Discussion_Topics__c = 'Reviewed post-surgical recovery protocols and adjuvant chemotherapy options.',
        Follow_Up_Actions__c = 'Schedule a lunch meeting to discuss adjuvant therapy trial enrollment.',
        AI_Summary__c      = 'Moderate engagement. Follow-up meeting needed to progress on trial enrollment.'
    ),
    new Visit_Report__c(
        Physician__c       = physicians[2].Id,
        Rep__c             = currentUserId,
        Visit_Date__c      = Date.today().addDays(-7),
        Visit_Outcome__c   = 'Neutral',
        Engagement_Score__c = 45,
        Discussion_Topics__c = 'Brief drop-in. Left product samples and updated formulary list.',
        AI_Summary__c      = 'Short visit, neutral outcome. Left samples. No immediate follow-up needed.'
    ),
    new Visit_Report__c(
        Physician__c       = physicians[3].Id,
        Rep__c             = currentUserId,
        Visit_Date__c      = Date.today().addDays(-5),
        Visit_Outcome__c   = 'Positive',
        Engagement_Score__c = 78,
        Discussion_Topics__c = 'Presented IMRT vs SABR outcomes data. Discussed referral pathway for complex cases.',
        Follow_Up_Actions__c = 'Arrange KOL speaker session for Bangalore territory.',
        AI_Summary__c      = 'Strong visit. Dr. Nair interested in KOL session. Referral pathway discussion promising.'
    ),
    new Visit_Report__c(
        Physician__c       = physicians[4].Id,
        Rep__c             = currentUserId,
        Visit_Date__c      = Date.today().addDays(-3),
        Visit_Outcome__c   = 'Negative',
        Engagement_Score__c = 28,
        Discussion_Topics__c = 'Discussed companion diagnostics partnership. Dr. Iyer expressed concerns about turnaround time.',
        Follow_Up_Actions__c = 'Escalate TAT concerns to medical affairs. Send updated diagnostics SLA document.',
        AI_Summary__c      = 'Difficult call. TAT concerns flagged. Immediate escalation to medical affairs required.'
    ),
    new Visit_Report__c(
        Physician__c       = physicians[0].Id,
        Rep__c             = currentUserId,
        Visit_Date__c      = Date.today().addDays(-1),
        Visit_Outcome__c   = 'Positive',
        Engagement_Score__c = 90,
        Discussion_Topics__c = 'Reviewed clinical trial enrolment numbers. Dr. Sharma agreed to refer 3 patients.',
        Follow_Up_Actions__c = 'Submit patient referral forms to CRO by end of week.',
        AI_Summary__c      = 'Excellent visit. 3 patient referrals committed. High priority account confirmed.'
    )
};
Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.allowSave = true;
List<Database.SaveResult> vResults = Database.insert(visits, dml);
System.debug('Inserted ' + visits.size() + ' visit reports');

// ── 5. VISIT EXPENSES ─────────────────────────────────────────────────────────
List<Visit_Expense__c> expenses = new List<Visit_Expense__c>{
    new Visit_Expense__c(
        Visit_Report__c = visits[0].Id,
        Category__c     = 'Meal',
        Amount__c       = 120,
        Notes__c        = 'Lunch with Dr. Sharma and 2 team members at Apollo cafeteria',
        Receipt_URL__c  = 'https://receipts.oncoglobal.in/R-2024-0001'
    ),
    new Visit_Expense__c(
        Visit_Report__c = visits[0].Id,
        Category__c     = 'Travel',
        Amount__c       = 45,
        Notes__c        = 'Cab fare to Apollo Cancer Centre and back',
        Receipt_URL__c  = 'https://receipts.oncoglobal.in/R-2024-0002'
    ),
    new Visit_Expense__c(
        Visit_Report__c = visits[1].Id,
        Category__c     = 'Meal',
        Amount__c       = 210,
        Notes__c        = 'Team dinner with Dr. Gupta and HOD — exceeded policy limit',
        Receipt_URL__c  = 'https://receipts.oncoglobal.in/R-2024-0003'
    ),
    new Visit_Expense__c(
        Visit_Report__c = visits[2].Id,
        Category__c     = 'Samples',
        Amount__c       = 80,
        Notes__c        = 'Dropped off 2 boxes of product samples',
        Receipt_URL__c  = 'https://receipts.oncoglobal.in/R-2024-0004'
    ),
    new Visit_Expense__c(
        Visit_Report__c = visits[3].Id,
        Category__c     = 'Travel',
        Amount__c       = 320,
        Notes__c        = 'Flight Mumbai to Bangalore for HCG visit',
        Receipt_URL__c  = 'https://receipts.oncoglobal.in/R-2024-0005'
    ),
    new Visit_Expense__c(
        Visit_Report__c = visits[3].Id,
        Category__c     = 'Accommodation',
        Amount__c       = 185,
        Notes__c        = 'Hotel stay in Bangalore (1 night)',
        Receipt_URL__c  = 'https://receipts.oncoglobal.in/R-2024-0006'
    ),
    new Visit_Expense__c(
        Visit_Report__c = visits[5].Id,
        Category__c     = 'CME / Event',
        Amount__c       = 250,
        Notes__c        = 'Sponsored CME session at Apollo — catering and materials',
        Receipt_URL__c  = 'https://receipts.oncoglobal.in/R-2024-0007'
    )
};
insert expenses;
System.debug('Inserted ' + expenses.size() + ' expenses');

// ── SUMMARY ──────────────────────────────────────────────────────────────────
System.debug('=== SAMPLE DATA INSERTED SUCCESSFULLY ===');
System.debug('Facilities : ' + facilities.size());
System.debug('Physicians : ' + physicians.size());
System.debug('Contacts   : ' + contacts.size());
System.debug('Visit Reports: ' + visits.size());
System.debug('Expenses   : ' + expenses.size());
System.debug('Policy-flagged expenses (Amount > 150): visits[1] Meal ₹210, visits[3] Travel ₹320, visits[3] Accommodation ₹185, visits[5] CME ₹250');
