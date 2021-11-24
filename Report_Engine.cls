/* Created By CBE1 */

public with sharing class Report_Engine {

    public virtual class BaseException extends Exception {}
    public class ReportNotFoundException extends BaseException {}
    public class UnknownFilterOperatorTypeException extends BaseException {}
    public class UnknownColumnTypeException extends BaseException {}
    public class FiltersLogicException extends BaseException {}
    public class MalformedQueryException extends BaseException {}

    public Report target;
    public String query;
    public Reports.ReportMetadata metadata;
    public String scopeObject;

    public Report_Engine(String devName) {
        List <Report> reportList = [SELECT Id,DeveloperName FROM Report where DeveloperName =: devName];
        if(reportList.isEmpty()) {
            throw new ReportNotFoundException('Report not found');
        }
        else {
            this.target = reportList.get(0);
            extractMeta((String)this.target.Id);
            buildQuery();
            checkQuery();
        }
    }

    /* 
    * Execute the built query to make sure the syntax is correct and everything has been generated correctly.
    */
    public void checkQuery() {
        Try{
            Database.query(this.query);
        } catch(Exception e) {
            throw new MalformedQueryException('La syntaxe de la query générée est mal formée, contactez un developpeur.');
        }
    }

    /*
    * Extract metadatas from the targetted report.
    */
    public void extractMeta(String reportId) {
        Reports.ReportResults results = Reports.ReportManager.runReport(reportId);
        this.metadata = results.getReportMetadata();
    }


    /*
    * Main logic here, looping over metadata to retreive columns, operators and values,
    * then dispatch data to the correct parsing methods.
    */
    public void buildQuery() {
        Reports.ReportMetadata rm = this.metadata;
        String logic = rm.getReportBooleanFilter();
        String query = 'SELECT ';

        System.debug('Report ' + this.target.DeveloperName);
        System.debug('---------------- TYPE -------------');
        Reports.ReportType typeReport = rm.getReportType();
        String objectToSelect = typeReport.getType();
        System.debug(objectToSelect);
        this.scopeObject = objectToSelect;
        System.debug('---------------- COLUMNS -------------');
        List<String> cols = rm.getDetailColumns();
        for(String champ : cols) {
            System.debug(parseColumnName(champ));
            query = query + parseColumnName(champ) + ', ';
        }
        query = query.substring(0,query.length()-2);


        query = query + ' FROM ' + objectToSelect;
        if(rm.getreportFilters().size()>0) {
            Map<Integer,String> fieldsByOfset = new Map<Integer,String>();
            Integer count = 0;
            Boolean flagFilter = false;
            query = query + ' WHERE';
            System.debug('---------------- FILTERS -------------');
            for(Reports.ReportFilter rf : rm.getreportFilters()){
                System.debug('[+] report filter type : ' + rf.getfilterType());
                if(rf.getfilterType()+'' == 'fieldValue') {
                    count++;
                    flagFilter = true;
                    String val = rf.getValue();
                    fieldsByOfset.put(count,parseOperator(rf.getcolumn(),rf.getoperator(),val));
                    val = parseColumnName(val);
                    system.debug(' |-> ' + rf.getcolumn() +' '+ rf.getoperator() +' '+ val);
                    if(logic == null) {
                        query = query + ' ' + parseOperator(rf.getcolumn(),rf.getoperator(),val) + ' AND';
                    }
                }
                else {
                    System.debug('[!] fieldType ' + rf.getfilterType() + ' not supported !');
                }
            }
            System.debug(fieldsByOfset.size());
            if(flagFilter == true && logic == null) {
                query = query.substring(0,query.length()-3);
            }
            else if(logic != null) {
                for(Integer key : fieldsByOfset.keySet()) {
                    if(!logic.contains(String.valueOf(key))) {
                        throw new FiltersLogicException('Le nombre de filtre ne correspond pas a la logique (type de filtre non géré).');
                    }
                    else {
                        logic = logic.replace(String.valueOf(key),fieldsByOfset.get(key));
                    }
                }
                query = query + ' ' + logic;
            }
        }
        System.debug(query);

        this.query = query;
    }

    /*
    * formats column's name, if it's a custom field, dereference the parent object because we are in SOQL syntax,
    * if it's a standard field, map the known report API name to a coherent standard API name.
    * Note that this method is the one that will change the most due to the hudge ammount of standards fields I didn't anticipate.
    */
    public String parseColumnName(String val) {
        if(val.contains(this.scopeObject+'.')) {
            return val.replace(this.scopeObject+'.', '');
        }
        else if(val == 'FULL_NAME') {
            return 'Owner.Name';
        }
        else if(val.endsWith('_ID') && val.startsWith(this.scopeObject.toUpperCase())) {
            return 'Id';
        }
        else if(val == 'STAGE_NAME') {
            return 'StageName';
        }
        else if(val == 'RECORDTYPE') {
            return 'RecordType.Name';
        }
        else if(val.endsWith('_NAME') && val.startsWith(this.scopeObject.toUpperCase())) {
            return 'Name';
        }
        else {
            return val;
        }
    }

    /*
    * Retrieve data type for the givent column, used to format data in filters.
    */
    public String getColumnType(String colName) {
        String schemaObj = this.scopeObject;
        String col = colName;
        if(colname.contains('.')) {
            schemaObj = colName.substring(0,colName.indexOf('.'));
            System.debug(schemaObj);
            col = colName.substring(colName.indexOf('.')+1,colName.length());
            System.debug(col);
        }
        SObjectType r = ((SObject)(Type.forName('Schema.'+schemaObj).newInstance())).getSObjectType();
        DescribeSObjectResult d = r.getDescribe();
        return String.valueOf(d.fields.getMap().get(col).getDescribe().getType());
    }

    /*
    * Format data in filters to match SOQL syntax according to data type and format.
    */
    public String parseFilterValueType(String field, String val) {
        String type = getColumnType(field);
        val = val.replace('"','');
        if(type == 'CURRENCY' || type == 'DOUBLE' || type == 'INTEGER' || type == 'LONG' || type == 'PERCENT' || type == 'BOOLEAN'){
            if(val == '') {
                val = '0';
            }
            if(val.contains(',')) {
                val = val.replace(',', '.');
            }
            return val;
        }
        else if(type == 'ADDRESS' || type == 'BASE64' || type == 'COMBOBOX' || type == 'DATE' || type == 'DATETIME' || type == 'EMAIL' || type == 'ENCRYPTEDSTRING' || type == 'ID' || type == 'LOCATION' || type == 'MULTIPICKLIST' || type == 'PHONE' || type == 'PICKLIST' || type == 'REFERENCE' || type == 'STRING' || type == 'TEXTAREA' || type == 'TIME' || type == 'URL'){
            return '\''+val+'\'';
        }
        else {
            throw new UnknownColumnTypeException('Type de champ ' + type + ' non supporté. (Contactez un developpeur)');
        }
        
    }

    /*
    * Parse operator to correct syntax and then concatenate it with columns name and filter value.
    */
    public String parseOperator(String field, String operator, String val) {
        field = parseColumnName(field);
        switch on operator {
            when 'equals' {
                return field + ' = ' + parseFilterValueType(field,val);
            }	
            when 'notEqual' {
                return field + ' != ' + parseFilterValueType(field,val);
            }
            when 'lessThan' {
                return field + ' < ' + parseFilterValueType(field,val);
            }
            when 'greaterThan' {
                return field + ' > ' + parseFilterValueType(field,val);
            }
            when 'lessOrEqual' {
                return field + ' <= ' + parseFilterValueType(field,val);
            }
            when 'greaterOrEqual' {
                return field + ' >= '+ parseFilterValueType(field,val);
            }
            when 'contains' {
                return field + ' LIKE \'%' + String.valueof(val) + '%\'';
            }
            when 'notContain' {
                return 'NOT ' + field + ' LIKE \'%' + String.valueof(val) + '%\'';
            }
            when 'startsWith' {
                return field + ' LIKE \'' + String.valueof(val) + '%\'';
            }
            when 'includes' {
                return field + ' INCLUDES (\'' + String.valueof(val) +'\')';
            }
            when 'excludes' {
                return field + ' EXCLUDES (\'' + String.valueof(val) +'\')';
            }
            when else {
                throw new UnknownFilterOperatorTypeException('Operateur ' + operator + ' non supporté. (Contactez un developpeur)');
            }
        }
    }

    // getters / setters
    public String getQuery() {
        return this.query;
    }
}
