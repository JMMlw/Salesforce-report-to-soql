# Salesforce-report-to-soql
Simple class to convert report to SOQL query


All sandard fields are not supported, you can add support for the api names not handled in method parseColumnName()
The reason is because fields API names in report are not the same as standard API names, for example an Opportunity's Name field will be OPPORTUNITY_NAME .

If someone re use it and implement api name support for fields I didn't, please do a merge request.
