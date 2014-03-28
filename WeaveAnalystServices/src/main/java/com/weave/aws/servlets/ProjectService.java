package weave.aws.servlets;

import java.rmi.RemoteException;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.json.simple.JSONObject;
import org.json.simple.parser.JSONParser;
import org.json.simple.parser.ParseException;

import weave.config.WeaveConfig;
import weave.servlets.WeaveServlet;
import weave.utils.SQLResult;
import weave.utils.SQLUtils;
import weave.utils.SQLUtils.WhereClause;

public class ProjectService extends WeaveServlet
{
	private static final long serialVersionUID = 1L;


	
	/**
	    * @param userName author of a given Project
	    * @param projectName project which contains queryObjects
	    * @return  collection of queryObjects in the project 
	    * @throws Exception
	    */
	//retrieves all the projects belonging to a particular user
	public String[] getProjectFromDatabase() throws SQLException, RemoteException{
		SQLResult projectObjects= null;//all the projects belonging to the userName
		
		Connection con = WeaveConfig.getConnectionConfig().getAdminConnection();
		String schema = WeaveConfig.getConnectionConfig().getDatabaseConfigInfo().schema;
		
		List<String> selectColumns = new ArrayList<String>();
		selectColumns.add("projectName");//we're retrieving the list of projects in the projectName column in database
		
//		Map<String,String> whereParams = new HashMap<String, String>();
//		whereParams.put("userName", userName);
//		Set<String> caseSensitiveFields  = new HashSet<String>(); 
//		queryObjects= SQLUtils.getResultFromQuery(con, query, params, false); OR
//		projectObjects = SQLUtils.getResultFromQuery(con,selectColumns, "data", "stored_query_objects", whereParams, caseSensitiveFields);
		
		
		String query = String.format("SELECT distinct(%s) FROM %s", "projectName", (SQLUtils.quoteSchemaTable(con,schema, "stored_query_objects")));
		projectObjects = SQLUtils.getResultFromQuery(con,query, null, true );
		
		String[] projectNames = new String[projectObjects.rows.length];
		for(int i = 0; i < projectObjects.rows.length; i++){
			Object project = projectObjects.rows[i][0];//TODO find better way to do this
			projectNames[i] = project.toString();

		}
		
		con.close();
		
		return projectNames;
	}
	

	/**

	 * 
	 * @param projectName
	 *            project from which queryObjects have to be listed
	 * @return finalQueryObjectCollection array of [jsonObjects, namesofFiles]
	 * @throws Exception
	 */
	// Gets the list of queryObjects in a folder and returns an array of
	// JSONObjects(each JSONObject --> one queryObject)
//	public Object[] getQueryObjectsInProject(String projectName)
//			throws Exception {
//		Object[] finalQueryObjectCollection = new Object[2];
//
//		JSONObject[] finalQueryObjects = null;
//		String[] queryNames = getQueryObjectNamesInProject(projectName);
//		if (queryNames.length != 0) {// if the project contains something
//			ArrayList<JSONObject> jsonlist = new ArrayList<JSONObject>();
//			JSONParser parser = new JSONParser();
//
//			finalQueryObjects = new JSONObject[queryNames.length];
//
//			for (int i = 0; i < queryNames.length; i++) {
//				// for every queryObject, convert to a json object
//				String extension = FilenameUtils.getExtension(queryNames[i]);
//
//				// add file filter for searching only for json files
//				if (extension.equalsIgnoreCase("json")) {
//					String path = "C:/Projects/" + projectName + "/"
//							+ queryNames[i];// TODO find better way
//					FileReader reader = new FileReader(path);
//					Object currentQueryObject = parser.parse(reader);
//					JSONObject currentjsonObject = (JSONObject) currentQueryObject;
//					jsonlist.add(currentjsonObject);
//					reader.close();
//				}
//			}
//
//			// returning an array of JSON Objects
//			finalQueryObjects = jsonlist.toArray(finalQueryObjects);
//		}
//
//		else {
//			// if project is empty return null
//			finalQueryObjects = null;
//			// throw new
//			// RemoteException("No query Objects found in the specified folder!");
//		}
//
//		finalQueryObjectCollection[0] = finalQueryObjects;
//		finalQueryObjectCollection[1] = queryNames;
//
//	}
		/*
 	    * @param userName author of a given Project
	    * @param projectName project which contains the requested query
	    * @param queryObjectName the filename that contains the requested queryObject
	    * @return the requested single queryObject 
	    * @throws Exception
	    */
	public SQLResult getSingleQueryObjectInProjectFromDatabase(String username, String projectName, String queryObjectName){
		SQLResult singleQueryObject = null;//the queryObject requested
		
		return singleQueryObject;
	};

	//Gets the sub-directories (projects) in the 'Projects' folder
//	public String[] getListOfProjects() 
//	{
//		File projects = new File("C:/", "Projects");
//		//File projects = new File(uploadPath, "Projects");
//		String[] projectNames = projects.list();
//		return projectNames; 
//	}
//	
	
//	public String[] getQueryObjectNamesInProject(String projectName)throws Exception
//	{
//		String[] queryObjectNames = null;
//		String pathq = "C:/Projects/" + projectName;
//		File queries = new File(pathq);
//		if(queries.exists()){
//			System.out.println("Exists");
//			queryObjectNames = queries.list();
//		}
//		return queryObjectNames;
//	}
//	
//	
	
   /** 
   * @param projectName project from which queryObjects have to be listed
   * @return finalQueryObjectCollection array of [jsonObjects, title of queryObjects]   
   * @throws Exception
   */
	public Object[] getQueryObjectsFromDatabase(String projectName) throws RemoteException, SQLException
	{
		Object[] finalQueryObjectCollection = new Object[3];
		
		Connection con = WeaveConfig.getConnectionConfig().getAdminConnection();
		String schema = WeaveConfig.getConnectionConfig().getDatabaseConfigInfo().schema;
		
		//we're retrieving the list of queryObjects in the selected project
		List<String> selectColumns = new ArrayList<String>();
		selectColumns.add("queryObjectTitle");
		selectColumns.add("queryObjectContent");
		selectColumns.add("projectDescription");
		
		
		Map<String,String> whereParams = new HashMap<String, String>();
		whereParams.put("projectName", projectName);
		Set<String> caseSensitiveFields  = new HashSet<String>();//empty 
		SQLResult queryObjectsSQLresult = SQLUtils.getResultFromQuery(con,selectColumns, schema, "stored_query_objects", whereParams, caseSensitiveFields);
		
		
		
		//getting names from queryObjectTitle
		String[] queryNames =  new String[queryObjectsSQLresult.rows.length];
		String projectDescription = null;
		for(int i = 0; i < queryObjectsSQLresult.rows.length; i++){
			Object singleSQLQueryObject = queryObjectsSQLresult.rows[i][0];//TODO find better way to do this
			queryNames[i] = singleSQLQueryObject.toString();
			
		}
		projectDescription = (queryObjectsSQLresult.rows[0][2]).toString();//TODO find better way to do this
		
		//getting json objects from queryObjectContent
		JSONObject[] finalQueryObjects = null;
		if(queryObjectsSQLresult.rows.length != 0)
		{
			ArrayList<JSONObject> jsonlist = new ArrayList<JSONObject>();
			JSONParser parser = new JSONParser();
			finalQueryObjects = new JSONObject[queryObjectsSQLresult.rows.length];
			
			
			for(int i = 0; i < queryObjectsSQLresult.rows.length; i++)
			{
				Object singleObject = queryObjectsSQLresult.rows[i][1];//TODO find better way to do this
				String singleObjectString = singleObject.toString();
				try{
					
					 Object parsedObject = parser.parse(singleObjectString);
					 JSONObject currentJSONObject = (JSONObject) parsedObject;
					
					 jsonlist.add(currentJSONObject);
				}
				catch (ParseException pe){
					
				}
				
			}//end of for loop
			
			finalQueryObjects = jsonlist.toArray(finalQueryObjects);
			
		}
		else{
			finalQueryObjects = null;
		}
		
		finalQueryObjectCollection[0] = finalQueryObjects;
		finalQueryObjectCollection[1] = queryNames;
		finalQueryObjectCollection[2] = projectDescription;
		con.close();
		return finalQueryObjectCollection;
		
	}
	

	
//	/**
//	    * 
//	    * @param projectName project from which queryObjects have to be listed
//	    * @return finalQueryObjectCollection array of [jsonObjects, namesofFiles] 
//	    * @throws Exception
//	    */
//	//Gets the list of queryObjects in a folder and returns an array of JSONObjects(each JSONObject --> one queryObject)
//	public Object[] getQueryObjectsInProject(String projectName) throws Exception
//	{
//		Object[] finalQueryObjectCollection = new Object[2];
//		
//		JSONObject[] finalQueryObjects = null;
//		String[] queryNames = getQueryObjectNamesInProject(projectName);
//		if(queryNames.length != 0)
//		{//if the project contains something
//			ArrayList<JSONObject> jsonlist = new ArrayList<JSONObject>();
//			JSONParser parser = new JSONParser();
//			
//			finalQueryObjects = new JSONObject[queryNames.length];
//			
//				for(int i =0; i < queryNames.length; i++)
//				{
//					//for every queryObject, convert to a json object
//					String extension = FilenameUtils.getExtension(queryNames[i]);
//					
//					//add file filter for searching only for json files
//					if(extension.equalsIgnoreCase("json"))
//					{
//						String path = "C:/Projects/"+projectName+"/"+queryNames[i];//TODO find better way
//						FileReader reader = new FileReader(path);
//						Object currentQueryObject = parser.parse(reader);
//						JSONObject currentjsonObject = (JSONObject) currentQueryObject;
//						jsonlist.add(currentjsonObject);
//						reader.close();
//					}
//				}
//					
//					//returning an array of JSON Objects
//				finalQueryObjects = jsonlist.toArray(finalQueryObjects);
//		}
//			
//			else{
//				//if project is empty return null
//				finalQueryObjects = null;
//				//throw new RemoteException("No query Objects found in the specified folder!");
//			}
//			
//			
//		finalQueryObjectCollection[0] = finalQueryObjects;
//		finalQueryObjectCollection[1] = queryNames;
//		
//		return finalQueryObjectCollection;
//		
//	}
	
	public int deleteProjectFromDatabase(String projectName)throws RemoteException, SQLException
	{
		Connection con = WeaveConfig.getConnectionConfig().getAdminConnection();
		String schema = WeaveConfig.getConnectionConfig().getDatabaseConfigInfo().schema;
		
		
		//Set<String> caseSensitiveFields  = new HashSet<String>(); 
		Map<String,Object> whereParams = new HashMap<String, Object>();
		whereParams.put("projectName", projectName);
		WhereClause<Object> clause = new WhereClause<Object>(con, whereParams, null, true);
		
		int count = SQLUtils.deleteRows(con, schema, "stored_query_objects",clause);
		con.close();
		return count;//number of rows deleted
	}
	
	
	public int deleteQueryObjectFromProjectFromDatabase(String projectName, String queryObjectTitle)throws RemoteException, SQLException{
		
		Connection con = WeaveConfig.getConnectionConfig().getAdminConnection();
		String schema = WeaveConfig.getConnectionConfig().getDatabaseConfigInfo().schema;
		Map<String,Object> whereParams = new HashMap<String, Object>();
		whereParams.put("projectName", projectName);
		whereParams.put("queryObjectTitle", queryObjectTitle);
		WhereClause<Object> clause = new WhereClause<Object>(con, whereParams, null, true);
		
		int count = SQLUtils.deleteRows(con, schema, "stored_query_objects",clause);
		con.close();
		return count;//number of rows deleted
	}
	//adds a queryObject to the database
	public int insertQueryObjectInProjectFromDatabase(String userName, String projectName, String queryObjectTitle, String queryObjectContent) throws RemoteException, SQLException
	{
		Connection con = WeaveConfig.getConnectionConfig().getAdminConnection();
		String schema = WeaveConfig.getConnectionConfig().getDatabaseConfigInfo().schema;
		Map<String,Object> record = new HashMap<String, Object>();
		record.put("userName", userName);
		record.put("projectName", projectName);
		record.put("queryObjectTitle", queryObjectTitle);
		record.put("queryObjectContent", queryObjectContent);
		
		int count = SQLUtils.insertRow(con, schema, "stored_query_objects", record );
		con.close();
		return count;//single row added
	}
	
	public int insertMultipleQueryObjectInProjectFromDatabase(String userName, String projectName,String projectDescription, String[] queryObjectTitle, String[] queryObjectContent) throws RemoteException, SQLException
	{
		Connection con = WeaveConfig.getConnectionConfig().getAdminConnection();
		String schema = WeaveConfig.getConnectionConfig().getDatabaseConfigInfo().schema;
		List<Map<String, Object>> records = new ArrayList<Map<String, Object>>();
		
		for(int i = 0; i < queryObjectTitle.length; i++){
			Map<String,Object> record = new HashMap<String, Object>();
			record.put("userName", userName);
			record.put("projectName", projectName);
			record.put("projectDescription", projectDescription);
			record.put("queryObjectTitle", queryObjectTitle[i]);
			record.put("queryObjectContent", queryObjectContent[i]);
			records.add(record);
		}
		
		
		int count = SQLUtils.insertRows(con, schema , "stored_query_objects", records );
		con.close();
		return count;
	}
	
	//deletes the entire specified folder (files within and folder itself)
//	public boolean deleteProject(String projectName) throws Exception
//	{
//		boolean status;
//		File pj = new File("C:/Projects", projectName);
//		status = FileUtils.deleteDirectory(pj);
//		
//		return status;
//	}
//	
	
	//deletes the specified file(json) within the specified folder
//	public boolean deleteQueryObject(String projectName, String queryObjectName) throws Exception
//	{
//		boolean status = false;
//		
//		String path = "C:/Projects/" + projectName + "/" + queryObjectName;//TODO find better way 
//		File fileToDelete = new File(path);
//		
//		if(fileToDelete.exists()){
//			fileToDelete.delete();
//			status = true;
//			System.out.println("deleted the file");
//		}
//	
//		return status;
//	}
//	
}


