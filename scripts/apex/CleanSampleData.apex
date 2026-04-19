// Deletes sample data inserted by InsertSampleData.apex
// Safe to run multiple times

// Delete Visit Expenses first (child)
List<Visit_Expense__c> expenses = [SELECT Id FROM Visit_Expense__c WHERE Visit_Report__r.Rep__c = :UserInfo.getUserId()];
if (!expenses.isEmpty()) { delete expenses; System.debug('Deleted ' + expenses.size() + ' expenses'); }

// Delete Visit Reports
List<Visit_Report__c> visits = [SELECT Id FROM Visit_Report__c WHERE Rep__c = :UserInfo.getUserId()];
if (!visits.isEmpty()) { delete visits; System.debug('Deleted ' + visits.size() + ' visit reports'); }

// Delete Contacts linked to sample physicians
List<Account> samplePhysicians = [SELECT Id FROM Account WHERE NPI__c IN ('1234567890','2345678901','3456789012','4567890123','5678901234')];
if (!samplePhysicians.isEmpty()) {
    List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId IN :samplePhysicians];
    if (!contacts.isEmpty()) { delete contacts; System.debug('Deleted ' + contacts.size() + ' contacts'); }
    delete samplePhysicians;
    System.debug('Deleted ' + samplePhysicians.size() + ' physicians');
}

// Delete sample facilities
List<Account> facilities = [SELECT Id FROM Account WHERE Name IN ('Apollo Cancer Centre','Tata Memorial Hospital','HCG Oncology Centre Bangalore')];
if (!facilities.isEmpty()) { delete facilities; System.debug('Deleted ' + facilities.size() + ' facilities'); }

System.debug('Cleanup complete');
