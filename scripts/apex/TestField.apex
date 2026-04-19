// Check namespace
Organization org = [SELECT NamespacePrefix FROM Organization LIMIT 1];
System.debug('Org namespace: ' + org.NamespacePrefix);

// Check for Best_Visit_Time variant
Map<String, Schema.SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();
for (String f : accFields.keySet()) {
    if (f.contains('best') || f.contains('abdm') || f.contains('enriched') || f.contains('visit_type') || f.contains('needs_review') || f.contains('total_visit_expense') || f.contains('policy_flag')) {
        System.debug('MATCH: ' + f + ' => ' + accFields.get(f).getDescribe().getLabel());
    }
}
// Check VR and Expense
Map<String, Schema.SObjectField> vrFields = Schema.SObjectType.Visit_Report__c.fields.getMap();
for (String f : vrFields.keySet()) {
    if (f.contains('visit_type') || f.contains('needs_review') || f.contains('total_visit')) {
        System.debug('VR MATCH: ' + f);
    }
}
Map<String, Schema.SObjectField> expFields = Schema.SObjectType.Visit_Expense__c.fields.getMap();
for (String f : expFields.keySet()) {
    if (f.contains('policy')) {
        System.debug('EXP MATCH: ' + f);
    }
}
