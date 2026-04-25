// OncoGlobal hackathon demo seed data.
// Creates 40 demo records for the core objects used by OncoFieldCopilotAgent.
// Run:
// sf apex run --file scripts/apex/SeedHackathonDemoData40.apex --target-org agentforce

String prefix = 'OG Demo';
Id currentUserId = UserInfo.getUserId();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> warnings = new List<String>();
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

// Cleanup from prior runs so counts remain demo-friendly.
delete [SELECT Id FROM Task WHERE Subject LIKE 'OG Demo%'];
delete [SELECT Id FROM Event WHERE Subject LIKE 'OG Demo%'];
if (gd.containsKey('ServiceAppointment')) {
    try {
        List<SObject> serviceAppointments = Database.query(
            'SELECT Id FROM ServiceAppointment WHERE Subject LIKE \'OG Demo%\''
        );
        if (!serviceAppointments.isEmpty()) {
            delete serviceAppointments;
        }
    } catch (Exception ex) {
        warnings.add('ServiceAppointment cleanup skipped: ' + ex.getMessage());
    }
}
delete [SELECT Id FROM Visit_Expense__c WHERE Notes__c LIKE 'OG Demo%'];
delete [SELECT Id FROM Expense_Line_Item__c WHERE Name LIKE 'OG Demo%'];
delete [SELECT Id FROM Expense__c WHERE Invoice_Number__c LIKE 'OGD-%' OR Vendor__c LIKE 'OG Demo%'];
List<Visit_Report__c> visitsForCleanup = [
    SELECT Id, AI_Summary__c, Discussion_Topics__c
    FROM Visit_Report__c
    WHERE Rep__c = :currentUserId
    LIMIT 5000
];
List<Visit_Report__c> seededVisitsForCleanup = new List<Visit_Report__c>();
for (Visit_Report__c visitForCleanup : visitsForCleanup) {
    if ((visitForCleanup.AI_Summary__c != null && visitForCleanup.AI_Summary__c.startsWith('OG Demo'))
        || (visitForCleanup.Discussion_Topics__c != null && visitForCleanup.Discussion_Topics__c.startsWith('OG Demo'))) {
        seededVisitsForCleanup.add(visitForCleanup);
    }
}
if (!seededVisitsForCleanup.isEmpty()) {
    delete seededVisitsForCleanup;
}
if (gd.containsKey('HealthcarePractitionerFacility')) {
    try {
        List<SObject> links = Database.query(
            'SELECT Id FROM HealthcarePractitionerFacility WHERE Name LIKE \'OG Demo%\''
        );
        if (!links.isEmpty()) {
            delete links;
        }
    } catch (Exception ex) {
        warnings.add('HealthcarePractitionerFacility cleanup by Name skipped: ' + ex.getMessage());
    }
}
if (gd.containsKey('HealthcareFacility')) {
    try {
        List<SObject> facilities = Database.query(
            'SELECT Id FROM HealthcareFacility WHERE Name LIKE \'OG Demo%\''
        );
        if (!facilities.isEmpty()) {
            delete facilities;
        }
    } catch (Exception ex) {
        warnings.add('HealthcareFacility cleanup skipped: ' + ex.getMessage());
    }
}
if (gd.containsKey('HealthcareProvider')) {
    try {
        List<SObject> providers = Database.query(
            'SELECT Id FROM HealthcareProvider WHERE Name LIKE \'OG Demo%\''
        );
        if (!providers.isEmpty()) {
            delete providers;
        }
    } catch (Exception ex) {
        warnings.add('HealthcareProvider cleanup skipped: ' + ex.getMessage());
    }
}
delete [SELECT Id FROM ContentDocument WHERE Title LIKE 'OG Demo%'];
delete [SELECT Id FROM Contact WHERE Email LIKE 'og.demo.%@oncoglobal.test'];
delete [SELECT Id FROM Account WHERE Name LIKE 'OG Demo%'];

// 1. Account: 40 provider/facility accounts.
List<Account> accounts = new List<Account>();
List<String> territories = new List<String>{
    'Mumbai South', 'Mumbai Central', 'Delhi NCR', 'Bangalore North', 'Hyderabad West',
    'Chennai East', 'Pune West', 'Kolkata Central'
};
List<String> specialties = new List<String>{
    'Oncology', 'Surgical Oncology', 'Radiation Oncology', 'Haematology', 'Pathology'
};
for (Integer i = 1; i <= 40; i++) {
    Account accountRecord = new Account(
        Name = prefix + ' Facility ' + String.valueOf(i).leftPad(3, '0'),
        Phone = '+91-90000-' + String.valueOf(10000 + i),
        BillingCity = territories[Math.mod(i, territories.size())],
        BillingState = 'Demo State',
        BillingCountry = 'India'
    );
    if (Schema.SObjectType.Account.fields.getMap().containsKey('Territory__c')) {
        accountRecord.put('Territory__c', territories[Math.mod(i, territories.size())]);
    }
    if (Schema.SObjectType.Account.fields.getMap().containsKey('Specialty__c')) {
        accountRecord.put('Specialty__c', specialties[Math.mod(i, specialties.size())]);
    }
    if (Schema.SObjectType.Account.fields.getMap().containsKey('Facility_Type__c')) {
        accountRecord.put('Facility_Type__c', Math.mod(i, 3) == 0 ? 'Cancer Centre' : 'Hospital');
    }
    if (Schema.SObjectType.Account.fields.getMap().containsKey('Relationship_Score__c')) {
        accountRecord.put('Relationship_Score__c', 40 + Math.mod(i * 7, 55));
    }
    if (Schema.SObjectType.Account.fields.getMap().containsKey('Engagement_Score__c')) {
        accountRecord.put('Engagement_Score__c', 35 + Math.mod(i * 9, 60));
    }
    if (Schema.SObjectType.Account.fields.getMap().containsKey('Key_Account__c')) {
        accountRecord.put('Key_Account__c', Math.mod(i, 5) == 0);
    }
    accounts.add(accountRecord);
}
insert accounts;
counts.put('Account', accounts.size());

// 2. Contact: 40 doctors.
List<Contact> contacts = new List<Contact>();
for (Integer i = 1; i <= 40; i++) {
    Contact contactRecord = new Contact(
        FirstName = 'Doctor',
        LastName = 'Demo ' + String.valueOf(i).leftPad(3, '0'),
        AccountId = accounts[i - 1].Id,
        Title = 'Consultant Oncologist',
        Department = specialties[Math.mod(i, specialties.size())],
        Phone = '+91-91000-' + String.valueOf(10000 + i),
        Email = 'og.demo.' + String.valueOf(i).leftPad(3, '0') + '@oncoglobal.test'
    );
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Specialty__c')) {
        contactRecord.put('Specialty__c', specialties[Math.mod(i, specialties.size())]);
    }
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Territory__c')) {
        contactRecord.put('Territory__c', territories[Math.mod(i, territories.size())]);
    }
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Relationship_Score__c')) {
        contactRecord.put('Relationship_Score__c', 35 + Math.mod(i * 8, 60));
    }
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Engagement_Score__c')) {
        contactRecord.put('Engagement_Score__c', 30 + Math.mod(i * 11, 65));
    }
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Prescribing_Potential__c')) {
        contactRecord.put('Prescribing_Potential__c', Math.mod(i, 4) == 0 ? 'High' : 'Medium');
    }
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Do_Not_Visit__c')) {
        contactRecord.put('Do_Not_Visit__c', false);
    }
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Last_Visit_Date__c')) {
        contactRecord.put('Last_Visit_Date__c', Date.today().addDays(-1 * Math.mod(i * 5, 80)));
    }
    if (Schema.SObjectType.Contact.fields.getMap().containsKey('Total_Visits__c')) {
        contactRecord.put('Total_Visits__c', Math.mod(i * 3, 25));
    }
    contacts.add(contactRecord);
}
insert contacts;
counts.put('Contact', contacts.size());

// 3. Visit_Report__c: 40 logged visits.
List<Visit_Report__c> visitReports = new List<Visit_Report__c>();
for (Integer i = 1; i <= 40; i++) {
    Visit_Report__c visit = new Visit_Report__c(
        Physician__c = accounts[i - 1].Id,
        Rep__c = currentUserId,
        Visit_Date__c = Date.today().addDays(-1 * Math.mod(i * 3, 90)),
        Visit_Outcome__c = Math.mod(i, 5) == 0 ? 'Follow-Up Required' : 'Positive',
        Engagement_Score__c = 45 + Math.mod(i * 6, 50),
        Discussion_Topics__c = 'OG Demo discussion ' + i + ': referrals, campaign update, and oncology event invite.',
        Follow_Up_Actions__c = 'OG Demo follow-up ' + i + ': send brochure, schedule lunch, and confirm next CME slot.',
        AI_Summary__c = 'OG Demo AI summary for doctor ' + i + '. Relationship needs structured follow-up.'
    );
    if (Schema.SObjectType.Visit_Report__c.fields.getMap().containsKey('Prescriber__c')) {
        visit.put('Prescriber__c', contacts[i - 1].Id);
    }
    if (Schema.SObjectType.Visit_Report__c.fields.getMap().containsKey('Hospital__c')) {
        visit.put('Hospital__c', accounts[i - 1].Id);
    }
    if (Schema.SObjectType.Visit_Report__c.fields.getMap().containsKey('Visit_Type__c')) {
        List<Schema.PicklistEntry> visitTypes = Schema.SObjectType.Visit_Report__c.fields.getMap()
            .get('Visit_Type__c')
            .getDescribe()
            .getPicklistValues();
        if (!visitTypes.isEmpty()) {
            visit.put('Visit_Type__c', visitTypes[Math.mod(i, visitTypes.size())].getValue());
        }
    }
    visitReports.add(visit);
}
insert visitReports;
counts.put('Visit_Report__c', visitReports.size());

// 4. Visit_Expense__c: 40 typed visit expenses.
List<Visit_Expense__c> visitExpenses = new List<Visit_Expense__c>();
for (Integer i = 1; i <= 40; i++) {
    Visit_Expense__c expense = new Visit_Expense__c(
        Visit_Report__c = visitReports[i - 1].Id,
        Category__c = Math.mod(i, 2) == 0 ? 'Meal' : 'Travel',
        Amount__c = 120 + Math.mod(i * 37, 700),
        Notes__c = 'OG Demo typed expense for field visit ' + i
    );
    if (Schema.SObjectType.Visit_Expense__c.fields.getMap().containsKey('GST_Invoice_Number__c')) {
        expense.put('GST_Invoice_Number__c', 'OGD-VIS-' + String.valueOf(i).leftPad(3, '0'));
    }
    if (Schema.SObjectType.Visit_Expense__c.fields.getMap().containsKey('Policy_Flag__c')) {
        expense.put('Policy_Flag__c', i > 30);
    }
    visitExpenses.add(expense);
}
insert visitExpenses;
counts.put('Visit_Expense__c', visitExpenses.size());

// 5. Expense__c: 40 uploaded receipt expenses.
List<Expense__c> uploadedExpenses = new List<Expense__c>();
for (Integer i = 1; i <= 40; i++) {
    Expense__c expense = new Expense__c(
        Vendor__c = 'OG Demo Vendor ' + String.valueOf(i).leftPad(3, '0'),
        Amount__c = 200 + Math.mod(i * 41, 900),
        Invoice_Number__c = 'OGD-UP-' + String.valueOf(i).leftPad(3, '0'),
        Invoice_Date__c = Date.today().addDays(-1 * Math.mod(i, 30)),
        Doctor__c = contacts[i - 1].Id
    );
    if (Schema.SObjectType.Expense__c.fields.getMap().containsKey('Category__c')) {
        expense.put('Category__c', Math.mod(i, 2) == 0 ? 'Meals' : 'Travel');
    }
    if (Schema.SObjectType.Expense__c.fields.getMap().containsKey('Expense_Category__c')) {
        expense.put('Expense_Category__c', Math.mod(i, 2) == 0 ? 'Meals' : 'Travel');
    }
    if (Schema.SObjectType.Expense__c.fields.getMap().containsKey('Description__c')) {
        expense.put('Description__c', 'OG Demo receipt upload for doctor visit ' + i);
    }
    if (Schema.SObjectType.Expense__c.fields.getMap().containsKey('Business_Purpose__c')) {
        expense.put('Business_Purpose__c', 'OG Demo receipt upload for doctor visit ' + i);
    }
    uploadedExpenses.add(expense);
}
insert uploadedExpenses;
counts.put('Expense__c', uploadedExpenses.size());

// 6. Expense_Line_Item__c: 40 line items linked to uploaded expenses.
List<Expense_Line_Item__c> lineItems = new List<Expense_Line_Item__c>();
for (Integer i = 1; i <= 40; i++) {
    Expense_Line_Item__c item = new Expense_Line_Item__c(
        Name = 'OG Demo Line Item ' + String.valueOf(i).leftPad(3, '0'),
        Expense__c = uploadedExpenses[i - 1].Id,
        Quantity__c = 1 + Math.mod(i, 3),
        Unit_Price__c = 80 + Math.mod(i * 29, 400)
    );
    lineItems.add(item);
}
insert lineItems;
counts.put('Expense_Line_Item__c', lineItems.size());

// 7. Task: 40 open follow-up tasks.
List<Task> tasks = new List<Task>();
for (Integer i = 1; i <= 40; i++) {
    tasks.add(new Task(
        Subject = 'OG Demo follow-up task ' + String.valueOf(i).leftPad(3, '0'),
        WhoId = contacts[i - 1].Id,
        WhatId = accounts[i - 1].Id,
        OwnerId = currentUserId,
        ActivityDate = Date.today().addDays(Math.mod(i, 14) + 1),
        Status = 'Not Started',
        Priority = Math.mod(i, 5) == 0 ? 'High' : 'Normal',
        Description = 'OG Demo task: send oncology brochure and confirm referral pathway.'
    ));
}
insert tasks;
counts.put('Task', tasks.size());

// 8. Event: 40 calendar events.
List<Event> events = new List<Event>();
for (Integer i = 1; i <= 40; i++) {
    Datetime startDt = Datetime.now().addDays(Math.mod(i, 21) + 1).addHours(Math.mod(i, 7));
    events.add(new Event(
        Subject = 'OG Demo doctor visit event ' + String.valueOf(i).leftPad(3, '0'),
        WhoId = contacts[i - 1].Id,
        WhatId = accounts[i - 1].Id,
        OwnerId = currentUserId,
        StartDateTime = startDt,
        EndDateTime = startDt.addMinutes(45),
        Description = 'OG Demo scheduled field visit.'
    ));
}
insert events;
counts.put('Event', events.size());

// 9. ContentVersion: 40 files. Salesforce automatically creates 40 ContentDocument records.
List<ContentVersion> versions = new List<ContentVersion>();
for (Integer i = 1; i <= 40; i++) {
    versions.add(new ContentVersion(
        Title = 'OG Demo Receipt ' + String.valueOf(i).leftPad(3, '0'),
        PathOnClient = 'og-demo-receipt-' + String.valueOf(i).leftPad(3, '0') + '.txt',
        VersionData = Blob.valueOf('OG Demo receipt file ' + i + '\nVendor: OG Demo Vendor\nAmount: ' + (200 + Math.mod(i * 41, 900))),
        FirstPublishLocationId = accounts[i - 1].Id
    ));
}
insert versions;
counts.put('ContentVersion', versions.size());
counts.put('ContentDocument', [
    SELECT COUNT()
    FROM ContentDocument
    WHERE Title LIKE 'OG Demo Receipt%'
]);

// 10. HealthcareProvider: 40 if createable in this org.
List<Id> healthcareProviderIds = new List<Id>();
if (gd.containsKey('HealthcareProvider') && gd.get('HealthcareProvider').getDescribe().isCreateable()) {
    Schema.DescribeSObjectResult hpDescribe = gd.get('HealthcareProvider').getDescribe();
    Map<String, Schema.SObjectField> hpFields = hpDescribe.fields.getMap();
    List<SObject> providers = new List<SObject>();
    for (Integer i = 1; i <= 40; i++) {
        SObject provider = gd.get('HealthcareProvider').newSObject();
        if (hpFields.containsKey('Name') && hpFields.get('Name').getDescribe().isCreateable()) {
            provider.put('Name', 'OG Demo Provider ' + String.valueOf(i).leftPad(3, '0'));
        }
        if (hpFields.containsKey('AccountId') && hpFields.get('AccountId').getDescribe().isCreateable()) {
            provider.put('AccountId', accounts[i - 1].Id);
        }
        if (hpFields.containsKey('PractitionerId') && hpFields.get('PractitionerId').getDescribe().isCreateable()) {
            provider.put('PractitionerId', contacts[i - 1].Id);
        }
        if (hpFields.containsKey('Npi') && hpFields.get('Npi').getDescribe().isCreateable()) {
            provider.put('Npi', 'OGD' + String.valueOf(1000000000 + i));
        }
        if (hpFields.containsKey('PrimarySpecialty') && hpFields.get('PrimarySpecialty').getDescribe().isCreateable()) {
            provider.put('PrimarySpecialty', specialties[Math.mod(i, specialties.size())]);
        }
        if (hpFields.containsKey('ProfessionalTitle') && hpFields.get('ProfessionalTitle').getDescribe().isCreateable()) {
            provider.put('ProfessionalTitle', 'Consultant Oncologist');
        }
        if (hpFields.containsKey('Status') && hpFields.get('Status').getDescribe().isCreateable()) {
            List<Schema.PicklistEntry> statusValues = hpFields.get('Status').getDescribe().getPicklistValues();
            if (!statusValues.isEmpty()) {
                provider.put('Status', statusValues[0].getValue());
            }
        }
        providers.add(provider);
    }
    List<Database.SaveResult> hpResults = Database.insert(providers, false);
    Integer hpSuccess = 0;
    for (Integer i = 0; i < hpResults.size(); i++) {
        if (hpResults[i].isSuccess()) {
            hpSuccess++;
            healthcareProviderIds.add((Id) providers[i].get('Id'));
        } else {
            warnings.add('HealthcareProvider row ' + (i + 1) + ': ' + hpResults[i].getErrors()[0].getMessage());
        }
    }
    counts.put('HealthcareProvider', hpSuccess);
} else {
    counts.put('HealthcareProvider', 0);
    warnings.add('HealthcareProvider is not createable in this org/user context.');
}

// 11. HealthcareFacility: 40 if createable.
List<Id> healthcareFacilityIds = new List<Id>();
if (gd.containsKey('HealthcareFacility') && gd.get('HealthcareFacility').getDescribe().isCreateable()) {
    Schema.DescribeSObjectResult hfDescribe = gd.get('HealthcareFacility').getDescribe();
    Map<String, Schema.SObjectField> hfFields = hfDescribe.fields.getMap();
    List<SObject> facilities = new List<SObject>();
    for (Integer i = 1; i <= 40; i++) {
        SObject facility = gd.get('HealthcareFacility').newSObject();
        if (hfFields.containsKey('Name') && hfFields.get('Name').getDescribe().isCreateable()) {
            facility.put('Name', 'OG Demo HC Facility ' + String.valueOf(i).leftPad(3, '0'));
        }
        if (hfFields.containsKey('AccountId') && hfFields.get('AccountId').getDescribe().isCreateable()) {
            facility.put('AccountId', accounts[i - 1].Id);
        }
        if (hfFields.containsKey('HealthcareProviderId') && hfFields.get('HealthcareProviderId').getDescribe().isCreateable() && i <= healthcareProviderIds.size()) {
            facility.put('HealthcareProviderId', healthcareProviderIds[i - 1]);
        }
        if (hfFields.containsKey('IsAlwaysOpen') && hfFields.get('IsAlwaysOpen').getDescribe().isCreateable()) {
            facility.put('IsAlwaysOpen', Math.mod(i, 2) == 0);
        }
        if (hfFields.containsKey('LicensedBedCount') && hfFields.get('LicensedBedCount').getDescribe().isCreateable()) {
            facility.put('LicensedBedCount', 50 + Math.mod(i * 11, 400));
        }
        if (hfFields.containsKey('LocationType') && hfFields.get('LocationType').getDescribe().isCreateable()) {
            List<Schema.PicklistEntry> locationValues = hfFields.get('LocationType').getDescribe().getPicklistValues();
            if (!locationValues.isEmpty()) {
                facility.put('LocationType', locationValues[0].getValue());
            }
        }
        facilities.add(facility);
    }
    List<Database.SaveResult> hfResults = Database.insert(facilities, false);
    Integer hfSuccess = 0;
    for (Integer i = 0; i < hfResults.size(); i++) {
        if (hfResults[i].isSuccess()) {
            hfSuccess++;
            healthcareFacilityIds.add((Id) facilities[i].get('Id'));
        } else {
            warnings.add('HealthcareFacility row ' + (i + 1) + ': ' + hfResults[i].getErrors()[0].getMessage());
        }
    }
    counts.put('HealthcareFacility', hfSuccess);
} else {
    counts.put('HealthcareFacility', 0);
    warnings.add('HealthcareFacility is not createable in this org/user context.');
}

// 12. HealthcarePractitionerFacility: 40 links if createable and parent records exist.
if (gd.containsKey('HealthcarePractitionerFacility') && gd.get('HealthcarePractitionerFacility').getDescribe().isCreateable()
    && !healthcareProviderIds.isEmpty() && !healthcareFacilityIds.isEmpty()) {
    Schema.DescribeSObjectResult hpfDescribe = gd.get('HealthcarePractitionerFacility').getDescribe();
    Map<String, Schema.SObjectField> hpfFields = hpfDescribe.fields.getMap();
    List<SObject> links = new List<SObject>();
    Integer linkLimit = Math.min(40, Math.min(healthcareProviderIds.size(), healthcareFacilityIds.size()));
    for (Integer i = 1; i <= linkLimit; i++) {
        SObject link = gd.get('HealthcarePractitionerFacility').newSObject();
        if (hpfFields.containsKey('Name') && hpfFields.get('Name').getDescribe().isCreateable()) {
            link.put('Name', 'OG Demo HC Link ' + String.valueOf(i).leftPad(3, '0'));
        }
        if (hpfFields.containsKey('HealthcareProviderId') && hpfFields.get('HealthcareProviderId').getDescribe().isCreateable()) {
            link.put('HealthcareProviderId', healthcareProviderIds[i - 1]);
        }
        if (hpfFields.containsKey('HealthcareFacilityId') && hpfFields.get('HealthcareFacilityId').getDescribe().isCreateable()) {
            link.put('HealthcareFacilityId', healthcareFacilityIds[i - 1]);
        }
        if (hpfFields.containsKey('PractitionerId') && hpfFields.get('PractitionerId').getDescribe().isCreateable()) {
            link.put('PractitionerId', contacts[i - 1].Id);
        }
        if (hpfFields.containsKey('IsActive') && hpfFields.get('IsActive').getDescribe().isCreateable()) {
            link.put('IsActive', true);
        }
        links.add(link);
    }
    List<Database.SaveResult> hpfResults = Database.insert(links, false);
    Integer hpfSuccess = 0;
    for (Integer i = 0; i < hpfResults.size(); i++) {
        if (hpfResults[i].isSuccess()) {
            hpfSuccess++;
        } else {
            warnings.add('HealthcarePractitionerFacility row ' + (i + 1) + ': ' + hpfResults[i].getErrors()[0].getMessage());
        }
    }
    counts.put('HealthcarePractitionerFacility', hpfSuccess);
} else {
    counts.put('HealthcarePractitionerFacility', 0);
    warnings.add('HealthcarePractitionerFacility not createable or missing Health Cloud parent records.');
}

// 13. ServiceAppointment: 40 if createable. Some Scheduler orgs require extra setup records.
if (gd.containsKey('ServiceAppointment') && gd.get('ServiceAppointment').getDescribe().isCreateable()) {
    Schema.DescribeSObjectResult saDescribe = gd.get('ServiceAppointment').getDescribe();
    Map<String, Schema.SObjectField> saFields = saDescribe.fields.getMap();
    List<SObject> serviceAppointments = new List<SObject>();
    for (Integer i = 1; i <= 40; i++) {
        Datetime startDt = Datetime.now().addDays(Math.mod(i, 25) + 2).addHours(Math.mod(i, 6));
        SObject appointment = gd.get('ServiceAppointment').newSObject();
        if (saFields.containsKey('Subject') && saFields.get('Subject').getDescribe().isCreateable()) {
            appointment.put('Subject', 'OG Demo service appointment ' + String.valueOf(i).leftPad(3, '0'));
        }
        if (saFields.containsKey('Description') && saFields.get('Description').getDescribe().isCreateable()) {
            appointment.put('Description', 'OG Demo generated appointment for field visit.');
        }
        if (saFields.containsKey('SchedStartTime') && saFields.get('SchedStartTime').getDescribe().isCreateable()) {
            appointment.put('SchedStartTime', startDt);
        }
        if (saFields.containsKey('SchedEndTime') && saFields.get('SchedEndTime').getDescribe().isCreateable()) {
            appointment.put('SchedEndTime', startDt.addMinutes(45));
        }
        if (saFields.containsKey('EarliestStartTime') && saFields.get('EarliestStartTime').getDescribe().isCreateable()) {
            appointment.put('EarliestStartTime', startDt.addHours(-1));
        }
        if (saFields.containsKey('DueDate') && saFields.get('DueDate').getDescribe().isCreateable()) {
            appointment.put('DueDate', startDt.addDays(1));
        }
        if (saFields.containsKey('Duration') && saFields.get('Duration').getDescribe().isCreateable()) {
            appointment.put('Duration', 45);
        }
        if (saFields.containsKey('DurationScale') && saFields.get('DurationScale').getDescribe().isCreateable()) {
            List<Schema.PicklistEntry> scaleValues = saFields.get('DurationScale').getDescribe().getPicklistValues();
            appointment.put('DurationScale', scaleValues.isEmpty() ? 'Minutes' : scaleValues[0].getValue());
        }
        if (saFields.containsKey('Status') && saFields.get('Status').getDescribe().isCreateable()) {
            List<Schema.PicklistEntry> statusValues = saFields.get('Status').getDescribe().getPicklistValues();
            appointment.put('Status', statusValues.isEmpty() ? 'None' : statusValues[0].getValue());
        }
        if (saFields.containsKey('ParentRecordId') && saFields.get('ParentRecordId').getDescribe().isCreateable()) {
            appointment.put('ParentRecordId', accounts[i - 1].Id);
        }
        if (saFields.containsKey('AccountId') && saFields.get('AccountId').getDescribe().isCreateable()) {
            appointment.put('AccountId', accounts[i - 1].Id);
        }
        if (saFields.containsKey('ContactId') && saFields.get('ContactId').getDescribe().isCreateable()) {
            appointment.put('ContactId', contacts[i - 1].Id);
        }
        serviceAppointments.add(appointment);
    }
    List<Database.SaveResult> saResults = Database.insert(serviceAppointments, false);
    Integer saSuccess = 0;
    for (Integer i = 0; i < saResults.size(); i++) {
        if (saResults[i].isSuccess()) {
            saSuccess++;
        } else {
            warnings.add('ServiceAppointment row ' + (i + 1) + ': ' + saResults[i].getErrors()[0].getMessage());
        }
    }
    counts.put('ServiceAppointment', saSuccess);
} else {
    counts.put('ServiceAppointment', 0);
    warnings.add('ServiceAppointment is not createable in this org/user context.');
}

System.debug('OG_DEMO_SEED_COUNTS ' + JSON.serializePretty(counts));
System.debug('OG_DEMO_SEED_WARNINGS ' + JSON.serializePretty(warnings));
