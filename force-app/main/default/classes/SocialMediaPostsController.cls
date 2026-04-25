public with sharing class SocialMediaPostsController {

    @AuraEnabled
    public static String generateFromFile(String contentDocumentId) {

        // 🔹 Step 1: Create ContentDocument input (IMPORTANT CHANGE)
        Map<String, String> contentDocumentMap = new Map<String, String>();
        contentDocumentMap.put('id', contentDocumentId);
        contentDocumentMap.put('type', 'ContentDocument'); // REQUIRED

        ConnectApi.WrappedValue contentDocumentValue = new ConnectApi.WrappedValue();
        contentDocumentValue.value = contentDocumentMap;

        // 🔹 Step 2: Input Params (MATCH TEMPLATE VARIABLE NAME)
        Map<String, ConnectApi.WrappedValue> inputParams =
            new Map<String, ConnectApi.WrappedValue>();

        inputParams.put('Input:ContentDocument', contentDocumentValue);

        // 🔹 Step 3: Configure invocation
        ConnectApi.EinsteinPromptTemplateGenerationsInput executeTemplateInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();

        executeTemplateInput.additionalConfig =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();

        executeTemplateInput.additionalConfig.applicationName = 'PromptBuilderPreview';
        executeTemplateInput.isPreview = false;
        executeTemplateInput.inputParams = inputParams;

        try {
            // 🔹 Step 4: Call Prompt Template
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    'extract_data_from_invoice', // ⚠️ Replace this
                    executeTemplateInput
                );

            // 🔹 Step 5: Extract response
            if (generationsOutput != null &&
                generationsOutput.generations != null &&
                !generationsOutput.generations.isEmpty()) {

                ConnectApi.EinsteinLLMGenerationItemOutput response =
                    generationsOutput.generations[0];

                return response.text;
            }

            return 'No response generated';

        } catch (Exception e) {
            System.debug('ERROR: ' + e.getMessage());
            System.debug('STACK: ' + e.getStackTraceString());
            throw new AuraHandledException('Error generating response: ' + e.getMessage());
        }
    }
}