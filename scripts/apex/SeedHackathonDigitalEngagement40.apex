// Optional Digital Engagement seed. Run after SeedHackathonDemoData40.apex.
// If 40 demo MessagingEndUser and MessagingSession records already exist,
// this script reports counts and skips inserts because active sessions cannot
// always be deleted in Salesforce.

Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> warnings = new List<String>();

Integer existingUsers = gd.containsKey('MessagingEndUser')
    ? Database.countQuery('SELECT COUNT() FROM MessagingEndUser WHERE Name LIKE \'OG Demo%\'')
    : 0;
Integer existingSessions = gd.containsKey('MessagingSession')
    ? Database.countQuery('SELECT COUNT() FROM MessagingSession WHERE ChannelName LIKE \'OG Demo%\'')
    : 0;

if (existingUsers >= 40 && existingSessions >= 40) {
    counts.put('MessagingEndUser', existingUsers);
    counts.put('MessagingSession', existingSessions);
} else {
    List<Contact> contacts = [
        SELECT Id, AccountId
        FROM Contact
        WHERE Email LIKE 'og.demo.%@oncoglobal.test'
        ORDER BY Email
        LIMIT 40
    ];

    Id channelId = null;
    Boolean createdChannelThisRun = false;
    if (gd.containsKey('MessagingChannel')) {
        List<SObject> existingChannels = Database.query(
            'SELECT Id FROM MessagingChannel WHERE DeveloperName = \'OG_Demo_Channel\' LIMIT 1'
        );
        if (!existingChannels.isEmpty()) {
            channelId = (Id) existingChannels[0].get('Id');
        }
    }

    if (channelId == null && gd.containsKey('MessagingChannel') && gd.get('MessagingChannel').getDescribe().isCreateable()) {
        Map<String, Schema.SObjectField> f = gd.get('MessagingChannel').getDescribe().fields.getMap();
        SObject channel = gd.get('MessagingChannel').newSObject();
        if (f.containsKey('DeveloperName') && f.get('DeveloperName').getDescribe().isCreateable()) channel.put('DeveloperName', 'OG_Demo_Channel');
        if (f.containsKey('MasterLabel') && f.get('MasterLabel').getDescribe().isCreateable()) channel.put('MasterLabel', 'OG Demo WhatsApp Channel');
        if (f.containsKey('MessagingPlatformKey') && f.get('MessagingPlatformKey').getDescribe().isCreateable()) channel.put('MessagingPlatformKey', 'og-demo-whatsapp');
        if (f.containsKey('IsActive') && f.get('IsActive').getDescribe().isCreateable()) channel.put('IsActive', true);
        if (f.containsKey('PlatformType') && f.get('PlatformType').getDescribe().isCreateable()) {
            List<Schema.PicklistEntry> values = f.get('PlatformType').getDescribe().getPicklistValues();
            if (!values.isEmpty()) channel.put('PlatformType', values[0].getValue());
        }
        if (f.containsKey('MessageType') && f.get('MessageType').getDescribe().isCreateable()) {
            List<Schema.PicklistEntry> values = f.get('MessageType').getDescribe().getPicklistValues();
            if (!values.isEmpty()) channel.put('MessageType', values[0].getValue());
        }
        Database.SaveResult sr = Database.insert(channel, false);
        if (sr.isSuccess()) {
            channelId = (Id) channel.get('Id');
            createdChannelThisRun = true;
            warnings.add('MessagingChannel was created. Rerun this script once to create MessagingEndUser and MessagingSession in a separate transaction.');
        } else {
            warnings.add('MessagingChannel create failed: ' + sr.getErrors()[0].getMessage());
        }
    }

    List<Id> endUserIds = new List<Id>();
    if (channelId != null && !createdChannelThisRun && gd.containsKey('MessagingEndUser') && gd.get('MessagingEndUser').getDescribe().isCreateable()) {
        Map<String, Schema.SObjectField> f = gd.get('MessagingEndUser').getDescribe().fields.getMap();
        List<SObject> rows = new List<SObject>();
        for (Integer i = 0; i < contacts.size(); i++) {
            SObject row = gd.get('MessagingEndUser').newSObject();
            if (f.containsKey('Name') && f.get('Name').getDescribe().isCreateable()) row.put('Name', 'OG Demo WhatsApp User ' + String.valueOf(i + 1).leftPad(3, '0'));
            if (f.containsKey('MessagingChannelId') && f.get('MessagingChannelId').getDescribe().isCreateable()) row.put('MessagingChannelId', channelId);
            if (f.containsKey('MessagingPlatformKey') && f.get('MessagingPlatformKey').getDescribe().isCreateable()) row.put('MessagingPlatformKey', '+9198000' + String.valueOf(10001 + i));
            if (f.containsKey('ContactId') && f.get('ContactId').getDescribe().isCreateable()) row.put('ContactId', contacts[i].Id);
            if (f.containsKey('AccountId') && f.get('AccountId').getDescribe().isCreateable()) row.put('AccountId', contacts[i].AccountId);
            if (f.containsKey('MessageType') && f.get('MessageType').getDescribe().isCreateable()) {
                List<Schema.PicklistEntry> values = f.get('MessageType').getDescribe().getPicklistValues();
                if (!values.isEmpty()) row.put('MessageType', values[0].getValue());
            }
            rows.add(row);
        }
        List<Database.SaveResult> results = Database.insert(rows, false);
        Integer ok = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                ok++;
                endUserIds.add((Id) rows[i].get('Id'));
            } else {
                warnings.add('MessagingEndUser row ' + (i + 1) + ': ' + results[i].getErrors()[0].getMessage());
            }
        }
        counts.put('MessagingEndUser', ok);
    } else {
        counts.put('MessagingEndUser', existingUsers);
    }

    if (channelId != null && !endUserIds.isEmpty() && gd.containsKey('MessagingSession') && gd.get('MessagingSession').getDescribe().isCreateable()) {
        Map<String, Schema.SObjectField> f = gd.get('MessagingSession').getDescribe().fields.getMap();
        List<SObject> rows = new List<SObject>();
        for (Integer i = 0; i < endUserIds.size(); i++) {
            SObject row = gd.get('MessagingSession').newSObject();
            if (f.containsKey('MessagingChannelId') && f.get('MessagingChannelId').getDescribe().isCreateable()) row.put('MessagingChannelId', channelId);
            if (f.containsKey('MessagingEndUserId') && f.get('MessagingEndUserId').getDescribe().isCreateable()) row.put('MessagingEndUserId', endUserIds[i]);
            if (f.containsKey('EndUserContactId') && f.get('EndUserContactId').getDescribe().isCreateable()) row.put('EndUserContactId', contacts[i].Id);
            if (f.containsKey('EndUserAccountId') && f.get('EndUserAccountId').getDescribe().isCreateable()) row.put('EndUserAccountId', contacts[i].AccountId);
            if (f.containsKey('ChannelKey') && f.get('ChannelKey').getDescribe().isCreateable()) row.put('ChannelKey', '+9198000' + String.valueOf(10001 + i));
            if (f.containsKey('ChannelName') && f.get('ChannelName').getDescribe().isCreateable()) row.put('ChannelName', 'OG Demo WhatsApp Session ' + String.valueOf(i + 1).leftPad(3, '0'));
            if (f.containsKey('StartTime') && f.get('StartTime').getDescribe().isCreateable()) row.put('StartTime', Datetime.now().addMinutes(-1 * (i + 1)));
            if (f.containsKey('Status') && f.get('Status').getDescribe().isCreateable()) {
                List<Schema.PicklistEntry> values = f.get('Status').getDescribe().getPicklistValues();
                if (!values.isEmpty()) row.put('Status', values[0].getValue());
            }
            rows.add(row);
        }
        List<Database.SaveResult> results = Database.insert(rows, false);
        Integer ok = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) ok++;
            else warnings.add('MessagingSession row ' + (i + 1) + ': ' + results[i].getErrors()[0].getMessage());
        }
        counts.put('MessagingSession', ok);
    } else {
        counts.put('MessagingSession', existingSessions);
    }
}

System.debug('OG_DEMO_DIGITAL_COUNTS ' + JSON.serializePretty(counts));
System.debug('OG_DEMO_DIGITAL_WARNINGS ' + JSON.serializePretty(warnings));
