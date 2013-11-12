/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.servlets;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.rmi.RemoteException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import weave.beans.RResult;
import weave.config.DataConfig.DataEntityMetadata;
import weave.servlets.DataService.FilteredColumnRequest;
import weave.utils.MapUtils;
import weave.utils.SQLUtils;

import com.google.gson.Gson;
import com.google.gson.internal.StringMap;

public class AWSRService extends RService
{
	private static final long serialVersionUID = 1L;

	public AWSRService()
	{

	}

	//TO DO write to and retrieve computation results from database
	//TO DO make it a map of the entire queryObject, of which the results is a property
	//temporary fix storing computation results in a hashmap
	public Map<String,RResult[]> compResultLookMap = new HashMap<String,RResult[]>();
	
	public void clearCache() {
		compResultLookMap.clear();
	}

	
	private Map<String,String> queryToMap(String query)
	{
		// Split it along &
		String[] pairs = query.split("&");
		Map<String,String> query_map = new HashMap<String,String>();
		for (String pair_str: pairs)
		{
			String[] pair = pair_str.split("=", 2);

			query_map.put(pair[0], pair[1]);
		}

		return query_map;
	}

	// this select query is the first version without filtering
	// we need to eventually replace it with the getQuery function in the DataService
	private String buildSelectQuery(String [] columns, String tableName)
	{
			int counter = columns.length;
			String tempQuery = "";
			
			for(int i=0; i < counter; i++)
			{
				String tempColumnName = SQLUtils.quoteSymbol(SQLUtils.MYSQL, columns[i]);

				if(i == (counter-1))
				{
					tempQuery = tempQuery.concat(tempColumnName);
				}
				else
					tempQuery = tempQuery.concat(tempColumnName + ", ");
			}
			
			String query = "select " + tempQuery + " from " + SQLUtils.quoteSymbol(SQLUtils.MYSQL, tableName);
			return query;
	}
	
	/**
	 * 
	 * @param requestObject sent from the AWS UI collection of parameters to run a computation
	 * @param connectionObject send from the AWS UI parameters needed for connection Rserve to the db
	 * @return returnedColumns result columns from the computation
	 * @throws Exception
	 */
	public RResult[] runScriptOnSQLColumns(Map<String,String> connectionObject, Map<String,Object> requestObject) throws Exception
	{
		RResult[] returnedColumns;
		String connectionType = connectionObject.get("connectionType").toString();
		String scriptName = requestObject.get("scriptName").toString();
		System.out.print(requestObject.toString());
		//if the computation result has been stored then computation is not run
		//the stored results are simply returned
		if(compResultLookMap.containsKey(requestObject.toString()))
		{
			return compResultLookMap.get(requestObject.toString());
		}
		
		else
		{
			//Set<String> keys = connectionObject.keySet();
			String user = connectionObject.get("user");
			String password = connectionObject.get("password");
			String schemaName = connectionObject.get("schema");
			String hostName = connectionObject.get("host");
			
				
			//String dataset = requestObject.get("dataset").toString();
			String scriptPath = requestObject.get("scriptPath").toString();
			//TODO Find better way to do this? full proof queries?
			//query construction
			Object columnNames = requestObject.get("columnsToBeRetrieved");//array list
			ArrayList<String> columns = new ArrayList<String>();
			columns = (ArrayList)columnNames;
			
			String col1 = columns.get(0);
			String col2 = columns.get(1);
			String col3 = columns.get(2);
			String col4 = columns.get(3);
			String col5 = columns.get(4);
			
			System.out.println(col1 + col2 + col3  + col4 + col5);
			String query = "";
			//String query = buildSelectQuery(columns, dataset);
			
			String cannedScriptLocation = scriptPath + scriptName;
			 //String cannedSQLScriptLocation = "C:\\Users\\Shweta\\Desktop\\" + (scriptName).toString();//hard coded for now
			 
			 Object[] requestObjectInputValues = {cannedScriptLocation, query, col1, col2, col3, col4, col5};
			 String[] requestObjectInputNames = {"cannedScriptPath", "query", "col1", "col2", "col3", "col4", "col5"};
			
			 String finalScript = "";
			 String dsn = connectionObject.get("dsn").toString();
			if(connectionType.equalsIgnoreCase("RMySQL"))
			{
				finalScript = "scriptFromFile <- source(cannedScriptPath)\n" +
							  "library(RMySQL)\n" +
							  "con <- dbConnect(dbDriver(\"MySQL\"), user =" + "\"" +user+"\" , password =" + "\"" +password+"\", host =" + "\"" +hostName+"\", port = 3306, dbname =" + "\"" +schemaName+"\")\n" +
							  "library(survey)\n" +
							  "getColumns <- function(query)\n" +
							  "{\n" +
							  "return(dbGetQuery(con, paste(query)))\n" +
							  "}\n" +
							  "returnedColumnsFromSQL <- scriptFromFile$value(query, params)\n";
			} else if (connectionType.equalsIgnoreCase("RODBC"))
			{
				finalScript ="scriptFromFile <- source(cannedScriptPath)\n" +
							 "library(RODBC)\n" +
							 "con <- odbcConnect(dsn =" + "\"" +dsn+"\", uid =" + "\"" +user+"\" , pwd =" + "\"" +password+"\")\n" +
							 "sqlQuery(con, \"USE " + schemaName + "\")\n" +
							 "library(survey)\n" +
							 "getColumns <- function(query)\n" +
							 "{\n" +
							 "return(sqlQuery(con, paste(query)))\n" +
							 "}\n" +
							 "returnedColumnsFromSQL <- scriptFromFile$value(query, params)\n";
			}
			String[] requestObjectOutputNames = {};
			
			returnedColumns = this.runScript( null, requestObjectInputNames, requestObjectInputValues, requestObjectOutputNames, finalScript, "", false, false, false);
			
			//rewriting?
			compResultLookMap.put(requestObject.toString(), returnedColumns);//temporary solution for caching. To be replaced by retrieval of computation results from db
			return returnedColumns;
		}
		 
	}
	
	/**
	 * 
	 * @param requestObject sent from the AWS UI collection of parameters to run a computation
	 * @param connectionObject send from the AWS UI parameters needed for connection Rserve to the db
	 * @param algorithmCollection collection of data mining algorithm objects to be run, eg KMeans, DIANA, CLARA etc
	 * @return returnedColumns result columns from the computation
	 * @throws Exception
	 */
	public RResult[] runScriptonAlgoCollection(Map<String,String> connectionObject, Map<String,Object> requestObject, Map<String,Object> algorithmParameters) throws Exception
	{
		RResult[] returnedColumns;
		String connectionType = connectionObject.get("connectionType").toString();
		String scriptName = requestObject.get("scriptName").toString();

		if(compResultLookMap.containsKey(requestObject.toString()))
		{
			return compResultLookMap.get(requestObject.toString());
		}
		
		else
		{
			
			ArrayList<String> inputNames = new ArrayList<String>();
			ArrayList<Object> inputValues = new ArrayList<Object>();
			
			String dataset = requestObject.get("dataset").toString();
			String scriptPath = requestObject.get("scriptPath").toString();
			Object columnNames = requestObject.get("columnsToBeRetrieved");//array list
			ArrayList<String> columnslist = new ArrayList<String>();
			columnslist = (ArrayList)columnNames;
			
			String [] columns = new String[columnslist.size()];
			columns = columnslist.toArray(columns);
			String query = buildSelectQuery(columns, dataset);
			String cannedScriptLocation = scriptPath + scriptName;
			
			inputNames.add("cannedScriptPath"); inputValues.add(cannedScriptLocation);
			inputNames.add("query"); inputValues.add(query);
			inputNames.add("params"); inputValues.add(columns);
			
			inputNames.add("myuser"); inputValues.add(connectionObject.get("user"));
			inputNames.add("mypassword"); inputValues.add(connectionObject.get("password"));
			inputNames.add("myhostName"); inputValues.add(connectionObject.get("host"));
			inputNames.add("myschemaName"); inputValues.add(connectionObject.get("schema"));
			inputNames.add("mydsn"); inputValues.add(connectionObject.get("dsn"));
			
			//looping through the parameters needed in the computational algorithms in r
			//if the map is not empty or if it exists
			if(!(algorithmParameters.isEmpty()) || algorithmParameters != null)
			{
				for(String key : algorithmParameters.keySet())
				{
					inputNames.add(key);
				}
				
				for(Object value : algorithmParameters.values())
				{
					inputValues.add(value);
				}
			}
				
						
			Object[] requestObjectInputValues = inputValues.toArray();
			String [] requestObjectInputNames = new String[requestObjectInputValues.length];
			inputNames.toArray(requestObjectInputNames);
			 
			//Object[] requestObjectInputValues = {cannedScriptLocation, query, columns, user, password, hostName, schemaName, dsn};
			// String[] requestObjectInputNames = {"cannedScriptPath", "query", "params", "myuser", "mypassword", "myhostName", "myschemaName", "mydsn"};
			
			 String finalScript = "";
			if(connectionType.equalsIgnoreCase("RMySQL"))
			{
				finalScript = "library(RMySQL)\n" +
							  "con <- dbConnect(dbDriver(\"MySQL\"), user = myuser , password = mypassword, host = myhostName, port = 3306, dbname =myschemaName)\n" +
							  "library(survey)\n" +
							   "getColumns <- function(query)\n" +
							  "{\n" +
							  "return(dbGetQuery(con, paste(query)))\n" +
							  "}\n" +
							   "scriptFromFile <- source(cannedScriptPath)\n" +
							   "returnedColumns <- scriptFromFile$value(ClusterSizes, Maxiterations, query)\n";
			} else if (connectionType.equalsIgnoreCase("RODBC"))
			{
				finalScript = "library(RODBC)\n" +
							 "con <- odbcConnect(dsn = mydsn, uid = myuser , pwd = mypassword)\n" +
							 "sqlQuery(con, \"USE myschemaName\")\n" +
							 "library(survey)\n" +
							 "getColumns <- function(query)\n" +
							 "{\n" +
							 "return(sqlQuery(con, paste(query)))\n" +
							 "}\n" +
							 "scriptFromFile <- source(cannedScriptPath)\n" +
							 "returnedColumnsFromSQL <- scriptFromFile$value(ClusterSizes, Maxiterations, query)\n";
			}
			String[] requestObjectOutputNames = {};
			
			returnedColumns = this.runScript( null, requestObjectInputNames, requestObjectInputValues, requestObjectOutputNames, finalScript, "", false, false, false);
			
			//rewriting?
			compResultLookMap.put(requestObject.toString(), returnedColumns);//temporary solution for caching. To be replaced by retrieval of computation results from db
			return returnedColumns;
		}
		 
	}
	
	public String[] getListOfScripts()
	{
		
		File directory = new File(uploadPath, "RScripts");
		String[] files = directory.list();
		List<String> rFiles = new ArrayList<String>();
		String extension = "";
		
		for (int i = 0; i < files.length; i++)
		{
			extension = files[i].substring(files[i].lastIndexOf(".") + 1, files[i].length());
			if(extension.equalsIgnoreCase("r"))
				rFiles.add(files[i]);
		}
		return rFiles.toArray(new String[rFiles.size()]);
	}


	/**
     * 
     * @param requestObject sent from the AWS UI collection of parameters to run a computation
     * @param connectionObject send from the AWS UI parameters needed for connection Rserve to the db
     * @return returnedColumns result columns from the computation
     * @throws Exception
     */
    public RResult[] runScriptwithScriptMetadata(Map<String,String> connectionObject, Map<String,Object> requestObject) throws Exception
    {
            RResult[] returnedColumns;
            String connectionType = connectionObject.get("connectionType").toString();
            String scriptName = requestObject.get("scriptName").toString();
            System.out.print(requestObject.toString());
            //if the computation result has been stored then computation is not run
            //the stored results are simply returned
            if(compResultLookMap.containsKey(requestObject.toString()))
            {
                    return compResultLookMap.get(requestObject.toString());
            }
            
            else
            {
                    //Set<String> keys = connectionObject.keySet();
                    String user = connectionObject.get("user");
                    String password = connectionObject.get("password");
                    String schemaName = connectionObject.get("schema");
                    String hostName = connectionObject.get("host");
                    String dsn = connectionObject.get("dsn").toString();
                    
                    String dataset = requestObject.get("dataset").toString();
                    String scriptPath = requestObject.get("scriptPath").toString();
                    
                    
                    //TODO Find better way to do this? full proof queries?
                    //query construction
                    Object columnNames = requestObject.get("columnsToBeRetrieved");//array list
                    ArrayList<String> columnslist = new ArrayList<String>();
                    columnslist = (ArrayList)columnNames;
                    
                    String [] columns = new String[columnslist.size()];
                    columns = columnslist.toArray(columns);
                    
                    String query = buildSelectQuery(columns, dataset);
                    
                    String cannedScriptLocation = scriptPath + scriptName;
                     
                    /*sending all necessary parameters to the database
                     * getting rid of string concatenation
                     * */
                     Object[] requestObjectInputValues = {cannedScriptLocation, query, columns, user, password, hostName, schemaName, dsn};
                     String[] requestObjectInputNames = {"cannedScriptPath", "query", "params", "myuser", "mypassword", "myhostName", "myschemaName", "mydsn"};
                    
                     String finalScript = "";
                    if(connectionType.equalsIgnoreCase("RMySQL"))
                    {
                            finalScript = "scriptFromFile <- source(cannedScriptPath)\n" +
                                                      "library(RMySQL)\n" +
                                                      "con <- dbConnect(dbDriver(\"MySQL\"), user = myuser , password = mypassword, host = myhostName, port = 3306, dbname =myschemaName)\n" +
                                                      "library(survey)\n" +
                                                      "getColumns <- function(query)\n" +
                                                      "{\n" +
                                                      "return(dbGetQuery(con, paste(query)))\n" +
                                                      "}\n" +
                                                      "returnedColumnsFromSQL <- scriptFromFile$value(query, params)\n";
                    } else if (connectionType.equalsIgnoreCase("RODBC"))
                    {
                            finalScript ="scriptFromFile <- source(cannedScriptPath)\n" +
                                                     "library(RODBC)\n" +
                                                     "con <- odbcConnect(dsn = mydsn, uid = myuser , pwd = mypassword)\n" +
                                                     "sqlQuery(con, \"USE myschemaName\")\n" +
                                                     "library(survey)\n" +
                                                     "getColumns <- function(query)\n" +
                                                     "{\n" +
                                                     "return(sqlQuery(con, paste(query)))\n" +
                                                     "}\n" +
                                                     "returnedColumnsFromSQL <- scriptFromFile$value(query, params)\n";
                    }
                    String[] requestObjectOutputNames = {};
                    
                    returnedColumns = this.runScript( null, requestObjectInputNames, requestObjectInputValues, requestObjectOutputNames, finalScript, "", false, false, false);
                    
                    //rewriting?
                    compResultLookMap.put(requestObject.toString(), returnedColumns);//temporary solution for caching. To be replaced by retrieval of computation results from db
                    return returnedColumns;
            }
             
    }        
    
    public Object getScriptMetadata(String scriptName) throws Exception
	{
		File directory = new File(uploadPath, "RScripts");
		String[] files = directory.list();
		int filecount = 0;
		// this object will get the metadata from the json file
		Object scriptMetadata = new Object();
		
		// we replace scriptname.R with scriptname.json
		String jsonFileName = scriptName.substring(0, scriptName.lastIndexOf('.')).concat(".json");

		// we will check if there is a json file with the same name in the directory.
		for (int i = 0; i < files.length; i++)
		{
			if (jsonFileName.equalsIgnoreCase(files[i]))
			{
				filecount++;
				// do the work
				Gson gson = new Gson();
				
				if(filecount > 1) {
					throw new RemoteException("multiple copies of " + jsonFileName + "found!");
				}
				
				try {
					
					BufferedReader br = new BufferedReader(new FileReader(new File(directory, jsonFileName)));
					
					scriptMetadata = gson.fromJson(br, Object.class);
					
					System.out.println(scriptMetadata);
				} catch (IOException e) {
					e.printStackTrace();
				}
			}
		}
		// 
		if(filecount == 0) {
			throw new RemoteException("Could not find the file " + jsonFileName + "!");
		}
		
		return scriptMetadata;
	}
    // this functions intends to run a script with filtered.
	// essentially this function should eventually be our main run script function.
	// in the request object, there will be: the script path, the script name
	// and the columns, along with their filters.
	// TODO not completed
	public RResult[] runScriptWithFilteredColumns(Map<String,Object> requestObject) throws Exception
	{
		RResult[] returnedColumns;

		String scriptName = requestObject.get("scriptName").toString();

		String cannedScript = uploadPath + "RScripts/" +scriptName;


		ArrayList<StringMap<Object>> columnRequests = (ArrayList<StringMap<Object>>) requestObject.get("FilteredColumnRequest");
		FilteredColumnRequest[] filteredColumnRequests = new FilteredColumnRequest[columnRequests.size()];
		StringMap<Object> theStringMapColumnRequest;
		FilteredColumnRequest filteredColumnRequest;
		
		for (int i = 0; i < columnRequests.size(); i++) {

			theStringMapColumnRequest = (StringMap<Object>) columnRequests.get(i);
			filteredColumnRequest = (FilteredColumnRequest) cast(theStringMapColumnRequest, FilteredColumnRequest.class);
			filteredColumnRequests[i] = filteredColumnRequest;
		}
		// Object filteredColumnRequests = requestObject.get("columnsToBeRetrieved");

		Object[][] recordData = DataService.getFilteredRows(filteredColumnRequests, null).recordData;
		Object[][] columnData = transpose(recordData);
		
		Object[] inputValues = {cannedScript, columnData};
		String[] inputNames = {"cannedScriptPath", "dataset"};

		String finalScript = "scriptFromFile <- source(cannedScriptPath)\n" +
					         "scriptFromFile$value(dataset)"; 

		String[] outputNames = {};
		returnedColumns = this.runScript(null, inputNames, inputValues, outputNames, finalScript, "", false, false, false);

		return returnedColumns;

	}
	
	public Object[][] transpose (Object[][] array) {
		  if (array == null || array.length == 0)//empty or unset array, nothing do to here
		    return array;

		  int width = array.length;
		  int height = array[0].length;

		  Object[][] array_new = new Object[height][width];

		  for (int x = 0; x < width; x++) {
		    for (int y = 0; y < height; y++) {
		      array_new[y][x] = array[x][y];
		    }
		  }
		  return array_new;
	}
	
    @SuppressWarnings("rawtypes")
    @Override
    protected Object cast(Object value, Class<?> type)
    {
    	if (type == FilteredColumnRequest.class && value != null && value instanceof Map)
    	{
    		FilteredColumnRequest fcr = new FilteredColumnRequest();
    		fcr.id = (Integer)cast(MapUtils.getValue((Map)value, "id", -1), int.class);
    		fcr.filters = (Object[])cast(MapUtils.getValue((Map)value, "filters", null), Object[].class);
    		if (fcr.filters != null)
    			for (int i = 0; i < fcr.filters.length; i++)
    			{
    				Object item = fcr.filters[i];
    				if (item != null && item.getClass() == ArrayList.class)
    					fcr.filters[i] = cast(item, Object[].class);
    			}
    		return fcr;
    	}
    	if (type == FilteredColumnRequest[].class && value != null && value.getClass() == Object[].class)
    	{
    		Object[] input = (Object[]) value;
    		FilteredColumnRequest[] output = new FilteredColumnRequest[input.length];
    		for (int i = 0; i < input.length; i++)
    		{
    			output[i] = (FilteredColumnRequest)cast(input[i], FilteredColumnRequest.class);
    		}
    		value = output;
    	}
    	if (type == DataEntityMetadata.class && value != null && value instanceof Map)
    	{
    		return DataEntityMetadata.fromMap((Map)value);
    	}
    	return super.cast(value, type);
    }
}