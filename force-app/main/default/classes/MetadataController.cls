public with sharing class MetadataController {
    public class ObjectInfo {
        @AuraEnabled public String QualifiedApiName;
        @AuraEnabled public String Label;
        @AuraEnabled public String KeyPrefix;
    }

    public class FieldInfo {
        @AuraEnabled public String QualifiedApiName;
        @AuraEnabled public String Label;
        @AuraEnabled public String DataType;
        @AuraEnabled public Boolean IsNillable;
        @AuraEnabled public Boolean IsUpdateable;
        @AuraEnabled public Boolean IsCreateable;
    }

    public class PicklistValueInfo {
        @AuraEnabled public String Value;
        @AuraEnabled public String Label;
        @AuraEnabled public Boolean IsActive;
        @AuraEnabled public Integer SortOrder;
    }

    public class ValidationRuleInfo {
        @AuraEnabled public String DeveloperName;
        @AuraEnabled public String ValidationName;
        @AuraEnabled public Boolean Active;
        @AuraEnabled public String ErrorMessage;
        @AuraEnabled public String ConditionFormula;
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectInfo> getObjects(String searchTerm) {
        List<ObjectInfo> results = new List<ObjectInfo>();
        String normalizedSearch = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();

        for (Schema.SObjectType objectType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult describeResult = objectType.getDescribe();
            if (!describeResult.isQueryable()) {
                continue;
            }

            String apiName = describeResult.getName();
            String label = describeResult.getLabel();
            if (
                normalizedSearch != null &&
                !apiName.toLowerCase().contains(normalizedSearch) &&
                !label.toLowerCase().contains(normalizedSearch)
            ) {
                continue;
            }

            ObjectInfo info = new ObjectInfo();
            info.QualifiedApiName = apiName;
            info.Label = label;
            info.KeyPrefix = describeResult.getKeyPrefix();
            results.add(info);
        }

        results.sort(new ObjectInfoSorter());
        if (results.size() <= 100) {
            return results;
        }

        List<ObjectInfo> trimmedResults = new List<ObjectInfo>();
        for (Integer index = 0; index < 100; index++) {
            trimmedResults.add(results[index]);
        }

        return trimmedResults;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getObjectFields(String objectName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null) {
            throw new AuraHandledException('Unknown object: ' + objectName);
        }

        List<FieldInfo> results = new List<FieldInfo>();
        Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>(fields.keySet());
        fieldNames.sort();

        for (String fieldName : fieldNames) {
            Schema.DescribeFieldResult describeResult = fields.get(fieldName).getDescribe();
            FieldInfo info = new FieldInfo();
            info.QualifiedApiName = describeResult.getName();
            info.Label = describeResult.getLabel();
            info.DataType = String.valueOf(describeResult.getType());
            info.IsNillable = describeResult.isNillable();
            info.IsUpdateable = describeResult.isUpdateable();
            info.IsCreateable = describeResult.isCreateable();
            results.add(info);
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistValueInfo> getPicklistValues(String objectName, String fieldName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null) {
            throw new AuraHandledException('Unknown object: ' + objectName);
        }

        Schema.SObjectField fieldRef = objectType.getDescribe().fields.getMap().get(fieldName);
        if (fieldRef == null) {
            throw new AuraHandledException('Unknown field: ' + objectName + '.' + fieldName);
        }

        List<PicklistValueInfo> results = new List<PicklistValueInfo>();
        Integer sortOrder = 0;
        for (Schema.PicklistEntry entry : fieldRef.getDescribe().getPicklistValues()) {
            PicklistValueInfo info = new PicklistValueInfo();
            info.Value = entry.getValue();
            info.Label = entry.getLabel();
            info.IsActive = entry.isActive();
            info.SortOrder = sortOrder;
            results.add(info);
            sortOrder++;
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<ValidationRuleInfo> getValidationRules(String objectName) {
        return new List<ValidationRuleInfo>();
    }

    public class ObjectInfoSorter implements Comparator<ObjectInfo> {
        public Integer compare(ObjectInfo leftValue, ObjectInfo rightValue) {
            String leftLabel = leftValue == null || leftValue.Label == null ? '' : leftValue.Label;
            String rightLabel = rightValue == null || rightValue.Label == null ? '' : rightValue.Label;
            return leftLabel.toLowerCase().compareTo(rightLabel.toLowerCase());
        }
    }
}
