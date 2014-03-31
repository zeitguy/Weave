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

import static weave.config.WeaveConfig.getConnectionConfig;
import static weave.config.WeaveConfig.getDataConfig;
import static weave.config.WeaveConfig.getDocrootPath;
import static weave.config.WeaveConfig.getUploadPath;
import static weave.config.WeaveConfig.initWeaveConfig;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FilenameFilter;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.rmi.RemoteException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.Vector;

import javax.servlet.ServletConfig;
import javax.servlet.ServletException;

import weave.beans.UploadFileFilter;
import weave.beans.UploadedFile;
import weave.beans.WeaveFileInfo;
import weave.config.ConnectionConfig;
import weave.config.ConnectionConfig.ConnectionInfo;
import weave.config.ConnectionConfig.DatabaseConfigInfo;
import weave.config.DataConfig;
import weave.config.DataConfig.DataEntity;
import weave.config.DataConfig.DataEntityMetadata;
import weave.config.DataConfig.DataEntityWithRelationships;
import weave.config.DataConfig.DataType;
import weave.config.DataConfig.EntityHierarchyInfo;
import weave.config.DataConfig.EntityType;
import weave.config.DataConfig.PrivateMetadata;
import weave.config.DataConfig.PublicMetadata;
import weave.config.WeaveConfig;
import weave.config.WeaveContextParams;
import weave.geometrystream.GeometryStreamConverter;
import weave.geometrystream.SHPGeometryStreamUtils;
import weave.geometrystream.SQLGeometryStreamDestination;
import weave.utils.BulkSQLLoader;
import weave.utils.CSVParser;
import weave.utils.DBFUtils;
import weave.utils.FileUtils;
import weave.utils.ListUtils;
import weave.utils.ProgressManager.ProgressPrinter;
import weave.utils.SQLExceptionWithQuery;
import weave.utils.SQLResult;
import weave.utils.SQLUtils;
import weave.utils.Strings;

public class AdminService extends WeaveServlet implements IWeaveEntityManagementService
{
	private static final long serialVersionUID = 1L;
	private RemoteException initializationError = null;
	
	public AdminService()
	{
	}

	public void init(ServletConfig config)
		throws ServletException
	{
		super.init(config);
		initWeaveConfig(WeaveContextParams.getInstance(config.getServletContext()));
	}
	
	/**
	 * This function should be the first thing called by the Admin Console to initialize the servlet.
	 * If SQL config data migration is required, it will be done and periodic status updates will be written to the servlet output stream.
	 * @throws RemoteException Thrown when the DataConfig could not be initialized.
	 */
	public void initializeAdminService() throws RemoteException
	{
		try
		{
			try
			{
				PrintStream ps = new PrintStream(getServletOutputStream());
				ProgressPrinter pp = new ProgressPrinter(ps);
				WeaveConfig.initializeAdminService(pp.getProgressManager());
			}
			catch (IOException e)
			{
				throw new RemoteException("Unable to initialize admin service", e);
			}
			initializationError = null;
		}
		catch (RemoteException e)
		{
			initializationError = e;
			throw e;
		}
	}
	
	public boolean checkDatabaseConfigExists() throws RemoteException
	{
		if (initializationError != null)
			throw initializationError;
		
		DatabaseConfigInfo dbInfo = getConnectionConfig().getDatabaseConfigInfo();
		return dbInfo != null;
		
		//TODO: if getConnectionConfig().getAdminConnection() fails, ask user to set up databaseConfig (other GUI should be hidden)
	}

	
	/**
	 * @param user
	 * @param password
	 * @return true if the user has superuser privileges.
	 * @throws RemoteException If authentication fails.
	 */
	public boolean authenticate(String user, String password) throws RemoteException
	{
		return getConnectionInfo(user, password).is_superuser;
	}
	
	private ConnectionInfo getConnectionInfo(String user, String password) throws RemoteException
	{
		ConnectionConfig connConfig = getConnectionConfig();
		ConnectionInfo info = connConfig.getConnectionInfo(user);
		if (info == null || password == null || !password.equals(info.pass))
		{
			System.out.println(String.format("authenticate failed, name=\"%s\" pass=\"%s\"", user, password));
			throw new RemoteException("Incorrect username or password.");
		}
		return info;
	}
	
    private void tryModify(String user, String pass, int entityId) throws RemoteException
    {
        if (getConnectionInfo(user, pass).is_superuser)
        	return; // superuser can modify anything
        
    	DataEntity entity = getDataConfig().getEntity(entityId);
    	String entityType = entity == null ? null : entity.publicMetadata.get(PublicMetadata.ENTITYTYPE);
    	
    	// permissions only supported on data tables and columns
    	if (Strings.equal(entityType, EntityType.TABLE) || Strings.equal(entityType, EntityType.COLUMN))
    	{
	        String owner = entity.privateMetadata.get(PrivateMetadata.CONNECTION);
	        if (!user.equals(owner))
	        	throw new RemoteException(String.format("User \"%s\" cannot modify entity %s.", user, entityId));
    	}
    }
	
	//////////////////////////////
	// Weave client config files

	/**
	 * Return a list of Client Config files from docroot
	 * 
	 * @return A list of (xml) client config files existing in the docroot folder.
	 */
	public String[] getWeaveFileNames(String user, String password, Boolean showAllFiles)
		throws RemoteException
	{
		ConnectionInfo info = getConnectionInfo(user, password);
		File[] files = null;
		List<String> listOfFiles = new ArrayList<String>();
		FilenameFilter fileFilter = new FilenameFilter()
		{
			public boolean accept(File dir, String fileName)
			{
				return fileName.endsWith(".weave") || fileName.endsWith(".xml");
			}
		};

		if (showAllFiles == true)
		{
			try
			{
				String root = getDocrootPath();
				File rootFolder = new File(root);
				files = rootFolder.listFiles();

				for (File f : files)
				{
					if (!f.isDirectory())
						continue;
					File[] configs = f.listFiles(fileFilter);
					for (File configfile : configs)
					{
						listOfFiles.add(f.getName() + "/" + configfile.getName());
					}
				}
			}
			catch (SecurityException e)
			{
				throw new RemoteException("Permission error reading directory.", e);
			}
		}

		String path = getDocrootPath();
		if (!showAllFiles && !Strings.isEmpty(info.folderName))
			path = path + info.folderName + "/";

		File docrootFolder = new File(path);

		try
		{
			docrootFolder.mkdirs();
			files = docrootFolder.listFiles(fileFilter);
			for (File file : files)
			{
				if (file.isFile())
				{
					listOfFiles.add(((!showAllFiles && !Strings.isEmpty(info.folderName))
							? info.folderName + "/" : "") + file.getName().toString());
				}
			}
		}
		catch (SecurityException e)
		{
			throw new RemoteException("Permission error reading directory.", e);
		}

		Collections.sort(listOfFiles, String.CASE_INSENSITIVE_ORDER);
		return ListUtils.toStringArray(listOfFiles);
	}

	/**
	 * @param user
	 * @param password
	 * @param fileContent
	 * @param fileName
	 * @param overwriteFile
	 * @return A description of the success or failure of this function.
	 * @throws RemoteException
	 */
	public String saveWeaveFile(
			String user, String password, InputStream fileContent, String fileName, boolean overwriteFile)
		throws RemoteException
	{
		ConnectionInfo info = getConnectionInfo(user, password);

		try
		{
			// remove special characters
			fileName = fileName.replace("\\", "").replace("/", "");

			if (!fileName.toLowerCase().endsWith(".weave") && !fileName.toLowerCase().endsWith(".xml"))
				fileName += ".weave";

			String path = getDocrootPath();
			if (!Strings.isEmpty(info.folderName))
				path = path + info.folderName + "/";

			File file = new File(path + fileName);

			if (file.exists())
			{
				if (!overwriteFile)
					return String.format("File already exists and was not changed: \"%s\"", fileName);
				if (!info.is_superuser && Strings.isEmpty(info.folderName))
					return String.format(
							"User \"%s\" does not have permission to overwrite configuration files.  Please save under a new filename.",
							user);
			}

			FileUtils.copy(fileContent, new FileOutputStream(file));
		}
		catch (IOException e)
		{
			throw new RemoteException("Error occurred while saving file", e);
		}

		return "Successfully generated " + fileName + ".";
	}

	/**
	 * Delete a Client Config file from docroot
	 * 
	 * @return A String message indicating if file was deleted.
	 * 
	 */
	public String removeWeaveFile(String user, String password, String fileName)
		throws RemoteException, IllegalArgumentException
	{
		ConnectionInfo info = getConnectionInfo(user, password);

		if (!info.is_superuser && Strings.isEmpty(info.folderName))
			return String.format(
					"User \"%s\" does not have permission to remove configuration files.", user);

		String path = getDocrootPath();
		if (!Strings.isEmpty(info.folderName))
			path = path + info.folderName + "/";

		File f = new File(path + fileName);
		try
		{
			// Make sure the file or directory exists and isn't write protected
			if (!f.exists())
				throw new IllegalArgumentException("Delete: no such file or directory: " + fileName);

			if (!f.canWrite())
				throw new IllegalArgumentException("File cannot be deleted Delete: write protected: " + fileName);

			// If it is a directory, make sure it is empty
			if (f.isDirectory())
				throw new IllegalArgumentException("Cannot Delete a directory");

			// Attempt to delete it
			boolean success = f.delete();

			if (!success)
				throw new IllegalArgumentException("Delete: deletion failed");

			return "Successfully deleted file " + fileName;
		}
		catch (SecurityException e)
		{
			throw new RemoteException("File could not be deleted", e);
		}
	}

	public WeaveFileInfo getWeaveFileInfo(String user, String password, String fileName)
		throws RemoteException
	{
		authenticate(user, password);
		return new WeaveFileInfo(getDocrootPath(), fileName);
	}

	//////////////////////////////
	// ConnectionInfo management
	
	public String[] getConnectionNames(String user, String password)
		throws RemoteException
	{
		try
		{
			ConnectionConfig config = getConnectionConfig();
			// only check password and superuser privileges if dbInfo is valid
			if (config.getDatabaseConfigInfo() != null)
			{
				// non-superusers can't get connection info for other users
				if (!getConnectionInfo(user, password).is_superuser)
					return new String[] { user };
			}
			// otherwise, return all connection names
			String[] connectionNames = config.getConnectionInfoNames().toArray(new String[0]);
			Arrays.sort(connectionNames, String.CASE_INSENSITIVE_ORDER);
			return connectionNames;
		}
		catch (RemoteException se)
		{
			return new String[] {};
		}
	}

	public ConnectionInfo getConnectionInfo(String loginUser, String loginPass, String userToGet)
		throws RemoteException
	{
		// non-superusers can't get connection info
		if (getConnectionInfo(loginUser, loginPass).is_superuser)
			return getConnectionConfig().getConnectionInfo(userToGet);
		return null;
	}
	
	public String saveConnectionInfo(
			String currentUser, String currentPass,
			String newUser, String newPass,
			String folderName, boolean grantSuperuser, String connectString,
			boolean configOverwrite)
		throws RemoteException
	{
		if (newUser.equals(""))
			throw new RemoteException("Connection name cannot be empty.");

		ConnectionInfo newConnectionInfo = new ConnectionInfo();
		newConnectionInfo.name = newUser;
		newConnectionInfo.pass = newPass;
		newConnectionInfo.folderName = folderName;
		newConnectionInfo.is_superuser = true;
		newConnectionInfo.connectString = connectString;

		// if there are existing connections and DatabaseConfigInfo exists,
		// check the password. otherwise, allow anything.
		ConnectionConfig config = getConnectionConfig();
		
		if (config.getConnectionInfoNames().size() > 0 && config.getDatabaseConfigInfo() != null)
		{
			authenticate(currentUser, currentPass);

			// non-superusers can't save connection info
			if (!config.getConnectionInfo(currentUser).is_superuser)
				throw new RemoteException(String.format(
						"User \"%s\" does not have permission to modify connections.", currentUser));
			// is_superuser for the new connection will only be false if there
			// is an existing superuser connection and grantSuperuser is false.
			newConnectionInfo.is_superuser = grantSuperuser;
		}

		// test connection only - to validate parameters
		Connection conn = null;
		try
		{
			conn = newConnectionInfo.getConnection();
			SQLUtils.testConnection(conn);
		}
		catch (Exception e)
		{
			throw new RemoteException(
					String.format("The connection named \"%s\" was not created because the server could not"
							+ " connect to the specified database with the given parameters.", newConnectionInfo.name),
					e);
		}
		finally
		{
			// close the connection, as we will not use it later
			SQLUtils.cleanup(conn);
		}

		// if the connection already exists AND overwrite == false throw error
		if (!configOverwrite && config.getConnectionInfoNames().contains(newConnectionInfo.name))
		{
			throw new RemoteException(String.format(
					"The connection named \"%s\" already exists.  Action cancelled.", newConnectionInfo.name));
		}

		// generate config connection entry
		try
		{
			// do not delete if this is the last user (which must be a
			// superuser)
			Collection<String> connectionNames = config.getConnectionInfoNames();

			// check for number of superusers
			int numSuperUsers = 0;
			for (String name : connectionNames)
			{
				if (config.getConnectionInfo(name).is_superuser)
					++numSuperUsers;
				if (numSuperUsers >= 2)
					break;
			}
			// sanity check
			if (Strings.equal(currentUser, newUser) && numSuperUsers == 1 && !newConnectionInfo.is_superuser)
				throw new RemoteException("Cannot remove superuser privileges from last remaining superuser.");

			config.saveConnectionInfo(newConnectionInfo);
		}
		catch (Exception e)
		{
			e.printStackTrace();
			throw new RemoteException(String.format(
					"Unable to create connection entry named \"%s\": %s", newConnectionInfo.name, e.getMessage()), e);
		}

		return String.format("The connection named \"%s\" was created successfully.", newUser);
	}

	public String removeConnectionInfo(
			String loginUser, String loginPassword, String userToRemove)
		throws RemoteException
	{
		// allow only a superuser to remove a connection
		if (!getConnectionInfo(loginUser, loginPassword).is_superuser)
			throw new RemoteException("Only superusers can remove connections.");

		try
		{
			ConnectionConfig config = getConnectionConfig();
			
			if (!config.getConnectionInfoNames().contains(userToRemove))
				throw new RemoteException("Connection \"" + userToRemove + "\" does not exist.");
			
			// disallow removing databaseConfig connection
			DatabaseConfigInfo dbInfo = config.getDatabaseConfigInfo();
			if (dbInfo != null && dbInfo.connection.equals(userToRemove))
				throw new RemoteException(String.format("Cannot remove connection \"%s\" which is used to store configuration information.", userToRemove));

			// check for number of superusers
			Collection<String> connectionNames = config.getConnectionInfoNames();
			int numSuperUsers = 0;
			for (String name : connectionNames)
				if (config.getConnectionInfo(name).is_superuser)
					++numSuperUsers;
			// do not allow removal of last superuser
			if (numSuperUsers == 1 && loginUser.equals(userToRemove))
				throw new RemoteException("Cannot remove the only superuser.");

			config.removeConnectionInfo(userToRemove);
			return "Connection \"" + userToRemove + "\" was deleted.";
		}
		catch (Exception e)
		{
			e.printStackTrace();
			throw new RemoteException(e.getMessage());
		}
	}

	//////////////////////////////////
	// DatabaseConfigInfo management
	
	public DatabaseConfigInfo getDatabaseConfigInfo(String user, String password)
		throws RemoteException
	{
		DatabaseConfigInfo dbInfo = getConnectionConfig().getDatabaseConfigInfo();
		if (dbInfo != null)
			authenticate(user, password);
		return dbInfo;
	}

	public String setDatabaseConfigInfo(String user, String password, String schema)
		throws RemoteException
	{
		if (!getConnectionInfo(user, password).is_superuser)
			throw new RemoteException("Unable to store configuration information without superuser privileges.");
		
		//TODO: option to migrate all data from old db to new db?
		
		// create info object
		DatabaseConfigInfo info = new DatabaseConfigInfo();
		info.schema = schema;
		info.connection = user;
		getConnectionConfig().setDatabaseConfigInfo(info);

		return String.format(
				"The admin console will now use the \"%s\" connection to store configuration information.",
				user);
	}

	//////////////////////////
	// DataEntity management
	
	public void addParentChildRelationship(String user, String password, int parentId, int childId, int insertAtIndex) throws RemoteException
	{
		tryModify(user, password, parentId);
		getDataConfig().buildHierarchy(parentId, childId, insertAtIndex);
	}

	public void removeParentChildRelationship(String user, String password, int parentId, int childId) throws RemoteException
	{
		if (parentId == DataConfig.NULL)
			throw new RemoteException("removeParentChildRelationship() called with parentId=" + DataConfig.NULL);
		
		tryModify(user, password, parentId);
		getDataConfig().removeChild(parentId, childId);
	}

	public int newEntity(String user, String password, DataEntityMetadata meta, int parentId, int insertAtIndex) throws RemoteException
	{
		tryModify(user, password, parentId);
		return getDataConfig().newEntity(meta, parentId, insertAtIndex);
	}

	public int[] removeEntities(String user, String password, int[] entityIds) throws RemoteException
	{
		Collection<Integer> ids = new LinkedList<Integer>();
		for (int id : entityIds)
		{
			tryModify(user, password, id);
			ids.add(id);
		}
		return ListUtils.toIntArray( getDataConfig().removeEntities(ids) );
	}

	public void updateEntity(String user, String password, int entityId, DataEntityMetadata diff) throws RemoteException
	{
		tryModify(user, password, entityId);
		getDataConfig().updateEntity(entityId, diff);
	}
	
	public EntityHierarchyInfo[] getHierarchyInfo(String user, String pass, Map<String,String> publicMetadata) throws RemoteException
	{
		authenticate(user, pass);
		return getDataConfig().getEntityHierarchyInfo(publicMetadata);
	}

	public DataEntityWithRelationships[] getEntities(String user, String pass, int[] ids) throws RemoteException
	{
		authenticate(user, pass);
		DataConfig config = getDataConfig();
		Set<Integer> idSet = new HashSet<Integer>();
		for (int id : ids)
			idSet.add(id);
		DataEntity[] result = config.getEntities(idSet).toArray(new DataEntity[0]);
		for (int i = 0; i < result.length; i++)
		{
			int id = result[i].id;
			int[] parentIds = ListUtils.toIntArray( config.getParentIds(Arrays.asList(id)) );
			int[] childIds = ListUtils.toIntArray( config.getChildIds(id) );
			result[i] = new DataEntityWithRelationships(result[i], parentIds, childIds);
		}
		return Arrays.copyOf(result, result.length, DataEntityWithRelationships[].class);
	}

	public int[] findEntityIds(String user, String pass, DataEntityMetadata metadata) throws RemoteException
	{
		authenticate(user, pass);
		return ListUtils.toIntArray( getDataConfig().getEntityIds(metadata) );
	}
	
	public String[] findPublicFieldValues(String user, String pass, String fieldName, String valueSearch) throws RemoteException
	{
		authenticate(user, pass);
		throw new RemoteException("Not implemented yet");
	}
	
	///////////////////////
	// SQL info retrieval
	
	/**
	 * The following functions get information about the database associated with a given connection name.
	 */
	public String[] getSQLSchemaNames(String user, String password)
		throws RemoteException
	{
		try
		{
			Connection conn = getConnectionInfo(user, password).getStaticReadOnlyConnection();
			List<String> schemas = SQLUtils.getSchemas(conn);
			// don't want to list information_schema.
			ListUtils.removeIgnoreCase("information_schema", schemas);
			return ListUtils.toStringArray(getSortedUniqueValues(schemas, false));
		}
		catch (SQLException e)
		{
			throw new RemoteException("Unable to get schema list from database.", e);
		}
	}

	public String[] getSQLTableNames(String configConnectionName, String password, String schemaName)
		throws RemoteException
	{
		try
		{
			Connection conn = getConnectionInfo(configConnectionName, password).getStaticReadOnlyConnection();
			List<String> tables = SQLUtils.getTables(conn, schemaName);
			return ListUtils.toStringArray(getSortedUniqueValues(tables, false));
		}
		catch (SQLException e)
		{
			throw new RemoteException("Unable to get schema list from database.", e);
		}
	}

	public String[] getSQLColumnNames(String configConnectionName, String password, String schemaName, String tableName)
		throws RemoteException
	{
		try
		{
			Connection conn = getConnectionInfo(configConnectionName, password).getStaticReadOnlyConnection();
			List<String> columns = SQLUtils.getColumns(conn, schemaName, tableName);
			return ListUtils.toStringArray(columns);
		}
		catch (SQLException e)
		{
			throw new RemoteException("Unable to get column list from database.", e);
		}
	}

	/**
	 * @param values A list of string values which may contain duplicates.
	 * @param moveEmptyStringToEnd If set to true and "" is at the front of the list, "" is moved to the end.
	 * @return A sorted list of unique values found in the given list.
	 */
	private List<String> getSortedUniqueValues(List<String> values, boolean moveEmptyStringToEnd)
	{
		Set<String> uniqueValues = new HashSet<String>();
		uniqueValues.addAll(values);
		Vector<String> result = new Vector<String>(uniqueValues);
		Collections.sort(result, String.CASE_INSENSITIVE_ORDER);
		// if empty string is at beginning of sorted list, move it to the end of the list
		if (moveEmptyStringToEnd && result.size() > 0 && result.get(0).equals(""))
			result.add(result.remove(0));
		return result;
	}

	/////////////////
	// File uploads

	/**
	 * This function accepts an uploaded file.
	 * 
	 * @param fileName The name of the file.
	 * @param content The file content.
	 * @param append Set to true to append to an existing file.
	 */
	public void uploadFile(String user, String password, String fileName, InputStream content, boolean append)
		throws RemoteException
	{
		authenticate(user, password);
		
		// make sure the upload folder exists
		(new File(getUploadPath())).mkdirs();

		String filePath = getUploadPath() + fileName;
		try
		{
			FileUtils.copy(content, new FileOutputStream(filePath, append));
		}
		catch (Exception e)
		{
			throw new RemoteException("File upload failed.", e);
		}
	}

	public UploadedFile[] getUploadedCSVFiles()
		throws RemoteException
	{
		File directory = new File(getUploadPath());
		List<UploadedFile> list = new ArrayList<UploadedFile>();
		File[] listOfFiles = null;

		try
		{
			if (directory.isDirectory())
			{
				listOfFiles = directory.listFiles(new UploadFileFilter("csv"));
				for (File file : listOfFiles)
				{
					if (file.isFile())
					{
						UploadedFile uploadedFile = new UploadedFile(file.getName(), file.length(), file.lastModified());
						list.add(uploadedFile);
					}
				}
			}
		}
		catch (Exception e)
		{
			throw new RemoteException(e.getMessage());
		}

		int n = list.size();
		return list.toArray(new UploadedFile[n]);
	}

	public UploadedFile[] getUploadedSHPFiles()
		throws RemoteException
	{
		File directory = new File(getUploadPath());
		List<UploadedFile> list = new ArrayList<UploadedFile>();
		File[] listOfFiles = null;

		try
		{
			if (directory.isDirectory())
			{
				listOfFiles = directory.listFiles(new UploadFileFilter("shp"));
				for (File file : listOfFiles)
				{
					if (file.isFile())
					{
						UploadedFile uploadedFile = new UploadedFile(file.getName(), file.length(), file.lastModified());
						list.add(uploadedFile);
					}
				}
			}
		}
		catch (Exception e)
		{
			throw new RemoteException(e.getMessage());
		}

		int n = list.size();
		return list.toArray(new UploadedFile[n]);
	}

	/**
	 * Read a list of csv files and return common header columns.
	 * 
	 * @param csvFile A CSV file name
	 * @return A list of common header files or null if none exist encoded using
	 * 
	 */
	public String[] getCSVColumnNames(String csvFile)
		throws RemoteException
	{
		String[] headerLine = null;

		try
		{
			BufferedReader in = new BufferedReader(new FileReader(new File(getUploadPath(), csvFile)));
			String header = in.readLine();
			if (header == null)
				throw new RemoteException("File is empty: " + csvFile);
			String[][] rows = CSVParser.defaultParser.parseCSV(header, true);
			headerLine = rows[0];
		}
		catch (FileNotFoundException e)
		{
			throw new RemoteException(e.getMessage());
		}
		catch (Exception e)
		{
			throw new RemoteException(e.getMessage());
		}

		return headerLine;
	}

	public String[] getDBFColumnNames(String[] dbfFileNames)
		throws RemoteException
	{
		try
		{
			Set<String> set = new HashSet<String>();
			List<String> list = new LinkedList<String>();
			for (String dbfFileName : dbfFileNames)
			{
				List<String> cols = DBFUtils.getAttributeNames(new File(getUploadPath(), correctFileNameCase(dbfFileName)));
				for (String col : cols)
				{
					if (!set.contains(col))
					{
						set.add(col);
						list.add(col);
					}
				}
			}
			return ListUtils.toStringArray(list);
		}
		catch (IOException e)
		{
			throw new RemoteException("IOException", e);
		}
	}
	
	private String correctFileNameCase(String fileName)
	{
		try
		{
			File directory = new File(getUploadPath());

			if (directory.isDirectory())
			{
				for (String file : directory.list())
				{
					if (file.equalsIgnoreCase(fileName))
						return file;
				}
			}
		}
		catch (Exception e)
		{
		}
		return fileName;
	}

	/////////////////////////////////
	// Key column uniqueness checks

	public void checkKeyColumnsForSQLImport(String connectionName, String password, String schemaName, String tableName, String[] keyColumns)
		throws RemoteException
	{
		ConnectionInfo info = getConnectionInfo(connectionName, password);
		
		if (info == null)
			throw new RemoteException(String.format("Connection named \"%s\" does not exist.", connectionName));

		Connection conn = null;
		String query = null;
		try
		{
			conn = info.getConnection();
			
			String quotedSchemaTable = SQLUtils.quoteSchemaTable(conn, schemaName, tableName);
			
			List<String> columnNames = SQLUtils.getColumns(conn, schemaName, tableName);
			for (String col : keyColumns)
				if (ListUtils.findString(col, columnNames) < 0)
					throw new RemoteException(String.format("SQL table %s does not have a column named \"%s\"", quotedSchemaTable, col));
	
			/* arguments to pass to String.format().*/
			Object[] formatArgs = new String[keyColumns.length + 1]; 
			formatArgs[0] = quotedSchemaTable;
			for (int i = 0; i < keyColumns.length; i++)
				formatArgs[i + 1] = SQLUtils.quoteSymbol(conn, keyColumns[i]);
			
			query = String.format(
					"select count(*) from %s group by " + Strings.mult(",", "%s", keyColumns.length) + " having count(*)>1",
					formatArgs
				);

			SQLResult result = SQLUtils.getResultFromQuery(conn, query, null, false);
			if (result.rows.length > 0)
				throw new RemoteException(String.format(
						"Values in the selected column%s do not uniquely identify rows in the table.",
						keyColumns.length == 1 ? "" : "s"
					));
		}
		catch (SQLException cause)
		{
			throw new RemoteException("Error querying key columns", new SQLExceptionWithQuery(query, cause));
		}
		finally
		{
			SQLUtils.cleanup(conn);
		}
	}
	
	/**
	 * Check if selected key column from CSV data has unique values
	 * @param csvFile The CSV file to check
	 * @param keyColumns The column names to check for unique values
	 * @throws RemoteException if the values in the key columns cannot be used to uniquely identify records.
	 */
	public void checkKeyColumnsForCSVImport(String csvFile, String[] keyColumns) throws RemoteException
	{
		if (keyColumns.length == 0)
			throw new RemoteException("No key columns specified");
		
		final CSVParser csvParser = CSVParser.defaultParser;

		String[][] rows;
		try
		{
			rows = csvParser.parseCSV(new File(getUploadPath(), csvFile), true);
		}
		catch (IOException cause)
		{
			if (cause instanceof RemoteException)
				throw (RemoteException)cause;
			throw new RemoteException(String.format("Unable to read file \"%s\"", csvFile), cause);
		}
		if (rows.length == 0)
			throw new RemoteException(String.format("File is empty: %s", csvFile));
		
		String[] headers = rows[0];
		
		HashMap<String, Integer> map = new HashMap<String, Integer>();
		int[] keyColumnIndices = new int[keyColumns.length];
			
		for (int i = 0; i < keyColumns.length;i++)
		{
			keyColumnIndices[i] = ListUtils.findString(keyColumns[i], headers);
			if (keyColumnIndices[i] < 0)
				throw new RemoteException(String.format("CSV file \"%s\" does not have a column named \"%s\"", csvFile, keyColumns[i]));
		}
		
		for (int row = 1; row < rows.length; row++)
		{
			String[] keyArray = ListUtils.getItems(rows[row], keyColumnIndices);
			String key = csvParser.createCSVRow(keyArray, true);
			if (!map.containsKey(key))
			{
				map.put(key, row);
			}
			else
			{
				int prevRow = map.get(key);
				String msg = String.format(
						"Found duplicate key (%s) on rows %s and %s of \"%s\"\n" +
						"Row %s: %s\n" +
						"Row %s: %s",
						key, prevRow, row, csvFile,
						prevRow, csvParser.createCSVRow(rows[prevRow], true),
						row, csvParser.createCSVRow(rows[row], true)
					);
				throw new RemoteException(msg);
			}
		}
	}
	public Boolean checkKeyColumnsForDBFImport(String[] fileNames, String[] keyColumnNames) throws IOException
	{
		if( fileNames.length == 0 || keyColumnNames.length == 0 )
			return false;
		
		File[] files = new File[fileNames.length];
		for (int i = 0; i < fileNames.length; i++)
			files[i] = new File(getUploadPath(), correctFileNameCase(fileNames[i]));
		
		return DBFUtils.isColumnUnique(files, keyColumnNames);
	}
	
	////////////////
	// Data import

	private boolean valueIsInt(String value)
	{
		try
		{
			return Integer.toString(Integer.parseInt(value)).equals(value);
		}
		catch (Exception e)
		{
			return false;
		}
	}

	/**
	 * @param value
	 * @return true if the value can be parsed as an int or double without losing information including leading zeros or whitespace padding.
	 */
	private boolean valueIsDouble(String value)
	{
		try
		{
			return Double.toString(Double.parseDouble(value)).equals(value) || valueIsInt(value);
		}
		catch (Exception e)
		{
			return false;
		}
	}
	
	private boolean isDuplicateItem(String[] items, int index)
	{
		for (int i = 0; i < items.length; i++)
			if (i != index && items[index].equals(items[i]))
				return true;
		return false;
	}

	public int importCSV(
			String connectionName, String password, String csvFile, String csvKeyColumn, String csvSecondaryKeyColumn,
			String sqlSchema, String sqlTable, boolean sqlOverwrite, String configDataTableName,
			String configKeyType, String[] nullValues,
			String[] filterColumnNames, boolean configAppend)
		throws RemoteException
	{
		ConnectionInfo connInfo = getConnectionInfo(connectionName, password);
		
		if (Strings.isEmpty(sqlSchema))
			throw new RemoteException("SQL schema must be specified.");
		if (Strings.isEmpty(sqlTable))
			throw new RemoteException("SQL table must be specified.");
		
		final int StringType = 0;
		final int IntType = 1;
		final int DoubleType = 2;
		
		if (sqlOverwrite && !connInfo.is_superuser)
			throw new RemoteException(String.format(
					"User \"%s\" does not have permission to overwrite SQL tables.", connectionName));

		Connection conn = null;
		Statement stmt = null;
		try
		{
			conn = connInfo.getConnection();

			sqlTable = sqlTable.toLowerCase(); // bug fix for MySQL running under Linux

			String[] sqlColumnNames = null;
			String[] csvColumnNames = null;
			int fieldLengths[] = null;

			// Load the CSV file and reformat it
			int[] types = null;

			boolean ignoreKeyColumnQueries = false;

			String[][] rows = CSVParser.defaultParser.parseCSV(new File(getUploadPath(), csvFile), true);

			if (rows.length == 0)
				throw new RemoteException("CSV file is empty: " + csvFile);
			
			// make sure rows all have the same length
			String[] firstRow = rows[0];
			for (int i = 0; i < rows.length; i++)
				if (rows[i].length != firstRow.length)
					rows[i] = Arrays.copyOf(rows[i], firstRow.length);

			// if there is no key column, we need to append a unique Row ID
			// column
			if ("".equals(csvKeyColumn))
			{
				ignoreKeyColumnQueries = true;

				csvKeyColumn = "row_id";
				for (int iRow = 0; iRow < rows.length; ++iRow)
				{
					String[] row = rows[iRow];
					String[] newRow = new String[row.length + 1];

					System.arraycopy(row, 0, newRow, 0, row.length);
					if (iRow == 0)
						newRow[newRow.length - 1] = csvKeyColumn;
					else
						newRow[newRow.length - 1] = "row" + iRow;
					rows[iRow] = newRow;
				}
			}

			// Read the column names

			sqlColumnNames = rows[0];
			csvColumnNames = new String[sqlColumnNames.length];
			fieldLengths = new int[sqlColumnNames.length];
			int keyColumnIndex = -1;
			int secondKeyColumnIndex = -1;
			// first, fix all column names
			for (int iCol = 0; iCol < sqlColumnNames.length; iCol++)
			{
				String colName = sqlColumnNames[iCol];
				if (Strings.isEmpty(colName))
					colName = "Column " + (iCol + 1);
				// save original column name
				csvColumnNames[iCol] = colName;
				// remember key col index
				if (Strings.equal(csvKeyColumn, colName))
					keyColumnIndex = iCol;
				if (Strings.equal(csvSecondaryKeyColumn, colName))
					secondKeyColumnIndex = iCol;
				
				sqlColumnNames[iCol] = SQLUtils.fixColumnName(colName, "");
			}
           	int[] filterColumnIndices = null;
           	if (filterColumnNames != null)
           	{
           		filterColumnIndices = new int[filterColumnNames.length];
           		for (int i = 0; i < filterColumnNames.length; i++)
           		{
           			int index = ListUtils.findString(filterColumnNames[i], csvColumnNames);
           			if (index < 0)
           				throw new RemoteException(String.format("CSV file \"%s\" has no column named \"%s\"", csvFile, filterColumnNames[i]));
           			filterColumnIndices[i] = index;
           		}
           	}
			
			// next, make sure there are no duplicates
			for (int iCol = 0; iCol < sqlColumnNames.length; iCol++)
			{
				if (isDuplicateItem(sqlColumnNames, iCol))
				{
					String match = sqlColumnNames[iCol];
					for (int i = 0; i < sqlColumnNames.length; i++)
					{
						if (match.equals(sqlColumnNames[i]))
						{
							sqlColumnNames[i] = SQLUtils.fixColumnName(match, "_" + i);
						}
					}
					// need to re-check all columns
					iCol = -1;
				}
			}

			// Initialize the types of columns as int (will be changed inside
			// loop if necessary)
			types = new int[sqlColumnNames.length];
			for (int iCol = 0; iCol < sqlColumnNames.length; iCol++)
			{
				fieldLengths[iCol] = 0;
				types[iCol] = IntType;
			}

			// Read the data and get the column type
			for (int iRow = 1; iRow < rows.length; iRow++)
			{
				String[] nextLine = rows[iRow];
				// Format each line
				for (int iCol = 0; iCol < sqlColumnNames.length && iCol < nextLine.length; iCol++)
				{
					// keep track of the longest String value found in this column
					fieldLengths[iCol] = Math.max(fieldLengths[iCol], nextLine[iCol].length());

					// Change missing data into NULL, later add more cases to deal with missing data.
					String[] nullValuesStandard = new String[] {
							"", ".", "..", " ", "-", "\"NULL\"", "NULL", "NaN" };
					ALL_NULL_VALUES: for (String[] values : new String[][] {
							nullValuesStandard, nullValues })
					{
						for (String nullValue : values)
						{
							if (nextLine[iCol] != null && nextLine[iCol].equalsIgnoreCase(nullValue))
							{
								nextLine[iCol] = null;

								break ALL_NULL_VALUES;
							}
						}
					}
					if (nextLine[iCol] == null)
						continue;

					try
					{
						// if the type was determined to be a string before, continue
						if (types[iCol] == StringType)
							continue;
						
						String value = nextLine[iCol];
						while (value.indexOf(',') > 0)
							value = value.replace(",", ""); // valid input format

						// if the type is an int (the default)
						if (types[iCol] == IntType)
						{
							// check that int is still acceptable
							if (valueIsInt(value))
								continue;
						}

						// it either wasn't an int or is no longer an int, check for a double
						if (valueIsDouble(value))
						{
							types[iCol] = DoubleType;
							continue;
						}

						// if we're down here, it must be a string
						types[iCol] = StringType;
					}
					catch (Exception e)
					{
						// this shouldn't happen, but it's just to be safe
						types[iCol] = StringType;
					}
				}
			}

			// now we need to remove commas from any numeric values because the SQL drivers don't like it
			for (int iRow = 1; iRow < rows.length; iRow++)
			{
				String[] nextLine = rows[iRow];
				// Format each line
				for (int iCol = 0; iCol < sqlColumnNames.length && iCol < nextLine.length; iCol++)
				{
					if (nextLine[iCol] == null)
						continue;
					String value = nextLine[iCol];
					if (types[iCol] == IntType || types[iCol] == DoubleType)
					{
						while (value.indexOf(",") >= 0)
							value = value.replace(",", "");
						nextLine[iCol] = value;
					}
				}
			}
			// Import the CSV file into SQL.
			// Drop the table if it exists.
			if (sqlOverwrite)
			{
				SQLUtils.dropTableIfExists(conn, sqlSchema, sqlTable);
			}
			else
			{
				if (ListUtils.findIgnoreCase(sqlTable, getSQLTableNames(connectionName, password, sqlSchema)) >= 0)
					throw new RemoteException("CSV not imported.\nSQL table already exists.");
			}

			// create a list of the column types
			List<String> columnTypesList = new Vector<String>();
			for (int iCol = 0; iCol < sqlColumnNames.length; iCol++)
			{
				if (types[iCol] == StringType || iCol == keyColumnIndex)
					columnTypesList.add(SQLUtils.getVarcharTypeString(conn, fieldLengths[iCol]));
				else if (types[iCol] == IntType)
					columnTypesList.add(SQLUtils.getIntTypeString(conn));
				else if (types[iCol] == DoubleType)
					columnTypesList.add(SQLUtils.getDoubleTypeString(conn));
			}
			// create the table
			SQLUtils.createTable(conn, sqlSchema, sqlTable, Arrays.asList(sqlColumnNames), columnTypesList, null);

			// import the data
			BulkSQLLoader loader = BulkSQLLoader.newInstance(conn, sqlSchema, sqlTable, sqlColumnNames);
			for (int iRow = 1; iRow < rows.length; iRow++) // skip header row
				loader.addRow((Object[])rows[iRow]);
			loader.flush();
			SQLUtils.cleanup(conn);

            DataEntityMetadata tableInfo = new DataEntityMetadata();
            tableInfo.setPrivateMetadata(
            	PrivateMetadata.IMPORTMETHOD, "importCSV",
            	PrivateMetadata.FILENAME, csvFile,
            	PrivateMetadata.KEYCOLUMN, csvKeyColumn
            );
			int table_id = addConfigDataTable(
					configDataTableName, connectionName,
					configKeyType, sqlColumnNames[keyColumnIndex], secondKeyColumnIndex, csvColumnNames, sqlColumnNames, sqlSchema,
					sqlTable, ignoreKeyColumnQueries, filterColumnIndices, tableInfo, configAppend);

            return table_id;
		}
		catch (RemoteException e) // required since RemoteException extends IOException
		{
			throw e;
		}
		catch (SQLException e)
		{
			throw new RemoteException("Import failed.", e);
		}
		catch (FileNotFoundException e)
		{
			e.printStackTrace();
			throw new RemoteException("File not found: " + csvFile);
		}
		catch (IOException e)
		{
			e.printStackTrace();
			throw new RemoteException("Cannot read file: " + csvFile);
		}
		finally
		{
			// close everything in reverse order
			SQLUtils.cleanup(stmt);
			SQLUtils.cleanup(conn);
		}
	}

	public int importSQL(
			String connectionName, String password, String schemaName, String tableName, String keyColumnName,
			String secondaryKeyColumnName, String configDataTableName,
			String keyType, String[] filterColumnNames, boolean append)
		throws RemoteException
	{
		authenticate(connectionName, password);
		
		if (Strings.isEmpty(schemaName))
			throw new RemoteException("SQL schema must be specified.");
		if (Strings.isEmpty(tableName))
			throw new RemoteException("SQL table must be specified.");
		
		String[] columnNames = getSQLColumnNames(connectionName, password, schemaName, tableName);
        DataEntityMetadata tableInfo = new DataEntityMetadata();
       	tableInfo.setPrivateMetadata(PrivateMetadata.IMPORTMETHOD, "importSQL");
       	int[] filterColumnIndices = null;
       	if (filterColumnNames != null)
       	{
       		filterColumnIndices = new int[filterColumnNames.length];
       		for (int i = 0; i < filterColumnNames.length; i++)
       		{
       			filterColumnIndices[i] = ListUtils.findString(filterColumnNames[i], columnNames);
       			if (filterColumnIndices[i] < 0)
       			{
       				throw new RemoteException(String.format(
       						"SQL table \"%s\" in schema \"%s\" has no column named \"%s\"",
       						tableName,
       						schemaName,
       						filterColumnNames[i]
       					));
       			}
       		}
       	}
       	
        int tableId = addConfigDataTable(
				configDataTableName,
				connectionName,
				keyType,
				keyColumnName,
				ListUtils.findString(secondaryKeyColumnName, columnNames),
				columnNames,
				columnNames,
				schemaName,
				tableName,
				false,
				filterColumnIndices,
				tableInfo,
				append
			);
        return tableId;
	}

	private int addConfigDataTable(
			String configDataTableName, String connectionName,
			String keyType, String sqlKeyColumn, int secondKeyColumnIndex,
			String[] configColumnNames, String[] sqlColumnNames, String sqlSchema, String sqlTable,
			boolean ignoreKeyColumnQueries, int[] filterColumnIndices, DataEntityMetadata tableImportInfo, boolean configAppend)
		throws RemoteException
	{
	    int table_id = DataConfig.NULL;	
		DataConfig dataConfig = getDataConfig();
		
		if (sqlColumnNames == null || sqlColumnNames.length == 0)
			throw new RemoteException("No columns were found.");
		ConnectionInfo connInfo = getConnectionConfig().getConnectionInfo(connectionName);
		if (connInfo == null)
			throw new RemoteException(String.format("Connection named \"%s\" does not exist.", connectionName));
		
		String failMessage = String.format("Failed to add DataTable \"%s\" to the configuration.\n", configDataTableName);
		String query = null;
		try
		{
			Connection conn = connInfo.getStaticReadOnlyConnection();
			
			// If key column is actually the name of a column, put quotes around it.  Otherwise, don't.
			String q_sqlKeyColumn;
			if (ListUtils.findString(sqlKeyColumn, sqlColumnNames) >= 0)
				q_sqlKeyColumn = SQLUtils.quoteSymbol(conn, sqlKeyColumn);
			else
				q_sqlKeyColumn = sqlKeyColumn;
			
			String q_sqlSecondKeyColumn = secondKeyColumnIndex >= 0
					? SQLUtils.quoteSymbol(conn, sqlColumnNames[secondKeyColumnIndex])
					: null;

			// Write SQL statements into sqlconfig.
			
			// generate and test each query before modifying config file
			List<ColumnInfo> columnInfoList = new Vector<ColumnInfo>();
			boolean foundMatchingColumnIds = false;
			
			SQLResult filteredValues = null;
			if (filterColumnIndices != null && filterColumnIndices.length > 0)
			{
				// get a list of unique combinations of filter values
				String columnList = "";
				for (int i = 0; i < filterColumnIndices.length; i++)
				{
					if (i > 0)
						columnList += ",";
					columnList += SQLUtils.quoteSymbol(conn, sqlColumnNames[filterColumnIndices[i]]);
				}
				
				query = String.format(
						"select distinct %s from %s order by %s",
						columnList,
						SQLUtils.quoteSchemaTable(conn, sqlSchema, sqlTable),
						columnList
					);
				filteredValues = SQLUtils.getResultFromQuery(conn, query, null, true);
				// System.out.println(query);
				// System.out.println(filteredValues);
			}
			
			String queryFormat = "SELECT %s,%s FROM %s";
			if (SQLUtils.isOracleServer(conn))
			{
				// workaround for ambiguous column name when filtering by rownum
				queryFormat = "SELECT %s thekey, %s thevalue FROM %s";
			}
			
			for (int iCol = 0; iCol < sqlColumnNames.length; iCol++)
			{
				String q_sqlColumn = sqlColumnNames[iCol];
				// System.out.println("columnName: " + columnName +
				// "\tkeyColumnName: " + keyColumnName + "\toriginalKeyCol: " +
				// originalKeyColumName);
				if (ignoreKeyColumnQueries && sqlKeyColumn.equals(q_sqlColumn))
					continue;
				q_sqlColumn = SQLUtils.quoteSymbol(conn, q_sqlColumn);

				// hack
				if (secondKeyColumnIndex >= 0)
					q_sqlColumn += "," + q_sqlSecondKeyColumn;

				// generate column query
				query = String.format(
						queryFormat,
						q_sqlKeyColumn,
						q_sqlColumn,
						SQLUtils.quoteSchemaTable(conn, sqlSchema, sqlTable)
					);

				DataEntityMetadata metaQuery = new DataEntityMetadata();
				metaQuery.setPublicMetadata(PublicMetadata.ENTITYTYPE, EntityType.COLUMN);
				metaQuery.setPrivateMetadata(
						PrivateMetadata.CONNECTION, connectionName,
						PrivateMetadata.SQLQUERY, query
					);
				if (filteredValues != null)
				{
					String filteredQuery = buildFilteredQuery(conn, query, filteredValues.columnNames);
					metaQuery.setPrivateMetadata(PrivateMetadata.SQLQUERY, filteredQuery);
					// generate one query per unique filter value combination
					for (int iRow = 0; iRow < filteredValues.rows.length; iRow++)
					{
						ColumnInfo info = new ColumnInfo();
						columnInfoList.add(info);
						
						info.schema = sqlSchema;
						info.table = sqlTable;
						info.column = sqlColumnNames[iCol];
						
						info.sqlParamsArray = filteredValues.rows[iRow];
						info.sqlParamsStr = CSVParser.defaultParser.createCSVRow(info.sqlParamsArray, true);
						info.title = buildFilteredColumnTitle(configColumnNames[iCol], info.sqlParamsArray);
						info.query = filteredQuery;
						testQueryAndGetDataType(conn, info);
						
						if (configAppend)
						{
							// try to find a matching column using private metadata: connection, sqlQuery, and sqlParams
							metaQuery.setPrivateMetadata(PrivateMetadata.SQLPARAMS, info.sqlParamsStr);
							info.existingColumnId = ListUtils.getFirstSortedItem(
									dataConfig.getEntityIds(metaQuery),
									DataConfig.NULL
								);
							if (info.existingColumnId != DataConfig.NULL)
								foundMatchingColumnIds = true;
						}
					}
				}
				else
				{
					ColumnInfo info = new ColumnInfo();
					columnInfoList.add(info);
					
					info.schema = sqlSchema;
					info.table = sqlTable;
					info.column = sqlColumnNames[iCol];
					
					info.title = configColumnNames[iCol];
					info.query = query;
					testQueryAndGetDataType(conn, info);
					
					if (configAppend)
					{
						// try to find a matching column using private metadata: connection and sqlQuery
						info.existingColumnId = ListUtils.getFirstSortedItem(
								dataConfig.getEntityIds(metaQuery),
								DataConfig.NULL
							);
						if (info.existingColumnId != DataConfig.NULL)
							foundMatchingColumnIds = true;
					}
				}
			}
			
			// done generating column info
			
			// determine if columns should be appended to an existing table
			int existingTableId = DataConfig.NULL;
			if (foundMatchingColumnIds)
			{
				// get the set of all matching column ids
				Set<Integer> columnIds = new HashSet<Integer>();
				for (ColumnInfo info : columnInfoList)
					columnIds.add(info.existingColumnId);
				// get parents of matching column ids
				Map<Integer,String> typeMap = dataConfig.getEntityTypes(dataConfig.getParentIds(columnIds));
				List<Integer> sortedParentIds = new ArrayList<Integer>(typeMap.keySet());
				Collections.sort(sortedParentIds);
				// find first matching parent table id
				for (int id : sortedParentIds)
				{
					if (Strings.equal(typeMap.get(id), EntityType.TABLE))
					{
						existingTableId = id;
						break;
					}
				}
			}
			
			DataEntityMetadata tableInfo = tableImportInfo == null ? new DataEntityMetadata() : tableImportInfo;
			tableInfo.setPublicMetadata(PublicMetadata.ENTITYTYPE, EntityType.TABLE);
        	tableInfo.setPrivateMetadata(
        		PrivateMetadata.CONNECTION, connectionName,
        		PrivateMetadata.SQLSCHEMA, sqlSchema,
        		PrivateMetadata.SQLTABLE, sqlTable,
        		PrivateMetadata.SQLKEYCOLUMN, sqlKeyColumn
        	);
        	
        	if (existingTableId == DataConfig.NULL)
        	{
        		// only set title if creating a new table
        		tableInfo.setPublicMetadata(PublicMetadata.TITLE, configDataTableName);
				table_id = dataConfig.newEntity(tableInfo, DataConfig.NULL, DataConfig.NULL);
        	}
        	else
        	{
        		table_id = existingTableId;
        		// update private metadata only
        		dataConfig.updateEntity(table_id, tableInfo);
        	}
			
			for (int i = 0; i < columnInfoList.size(); i++)
			{
				ColumnInfo info = columnInfoList.get(i);
				DataEntityMetadata newMeta = new DataEntityMetadata();
				
				// only set title on new columns
				if (existingTableId == DataConfig.NULL || info.existingColumnId == DataConfig.NULL)
					newMeta.setPublicMetadata(PublicMetadata.TITLE, info.title);
					
				newMeta.setPublicMetadata(
					PublicMetadata.ENTITYTYPE, EntityType.COLUMN,
					PublicMetadata.KEYTYPE, keyType,
					PublicMetadata.DATATYPE, info.dataType,
					PublicMetadata.PROJECTION, info.projection
				);
				newMeta.setPrivateMetadata(
					PrivateMetadata.CONNECTION, connectionName,
					PrivateMetadata.SQLQUERY, info.query,
					PrivateMetadata.SQLSCHEMA, info.schema,
					PrivateMetadata.SQLTABLE, info.table,
					PrivateMetadata.SQLKEYCOLUMN, sqlKeyColumn,
					PrivateMetadata.SQLCOLUMN, info.column
				);
				if (filteredValues != null)
				{
					newMeta.setPrivateMetadata(
						PrivateMetadata.SQLPARAMS, info.sqlParamsStr,
						PrivateMetadata.SQLFILTERCOLUMNS, CSVParser.defaultParser.createCSVRow(ListUtils.getItems(sqlColumnNames, filterColumnIndices), true)
					);
				}

				// if not updating an existing column, create a new one
				if (existingTableId == DataConfig.NULL || info.existingColumnId == DataConfig.NULL)
					dataConfig.newEntity(newMeta, table_id, DataConfig.NULL);
				else
					dataConfig.updateEntity(info.existingColumnId, newMeta);
			}
		}
		catch (SQLException e)
		{
			throw new RemoteException(failMessage, e);
		}
		catch (RemoteException e)
		{
			throw new RemoteException(failMessage, e);
		}

        return table_id;
	}
	
	class ColumnInfo
	{
		public String schema;
		public String table;
		public String column;
		public String title;
		public String query;
		public Object[] sqlParamsArray;
		public String sqlParamsStr;
		public String dataType;
		public String projection;
		public int existingColumnId = DataConfig.NULL;
	}
	
	/**
	 * This will test the query for a column and set the dataType and projection properties of a ColumnInfo object.
	 * @param conn An active SQL connection used to test the query.
	 * @param columnInfo All the info for the column, and the object which will hold the result.
	 */
	private void testQueryAndGetDataType(Connection conn, ColumnInfo info)
		throws RemoteException
	{
		String testQuery = info.query; // variable is used for error reporting and adding " limit 1" at the end.
		boolean shouldThrow = true;
		Statement stmt = null;
		ResultSet rs = null;
		try
		{
			if (SQLUtils.isSQLServer(conn))
			{
				String select_ = "select ";
				if (testQuery.toLowerCase().startsWith(select_))
					testQuery = "select top 1 " + testQuery.substring(select_.length());
			}
			else if (SQLUtils.isOracleServer(conn))
			{
				testQuery = "select * from (" + testQuery + ") where rownum = 1";
			}
			else
			{
				testQuery += " LIMIT 1";
			}

			if (info.sqlParamsArray == null || info.sqlParamsArray.length == 0)
			{
				// We have to use Statement when there are no parameters,
				// because CallableStatement
				// will fail in Microsoft SQL Server with
				// "Incorrect syntax near the keyword 'SELECT'".
				stmt = conn.createStatement();
				rs = stmt.executeQuery(testQuery);
			}
			else
			{
				stmt = SQLUtils.prepareStatement(conn, testQuery, info.sqlParamsArray);
				rs = ((PreparedStatement)stmt).executeQuery();
			}
			info.dataType = DataType.fromSQLType(rs.getMetaData().getColumnType(2));
			
			if (info.dataType.equals(DataType.GEOMETRY))
			{
				SQLUtils.cleanup(rs);
				SQLUtils.cleanup(stmt);
				
				// http://postgis.refractions.net/documentation/manual-1.5/ch04.html#spatial_ref_sys
				shouldThrow = false;
				testQuery = "SELECT CONCAT(auth_name,':',auth_srid) FROM public.spatial_ref_sys WHERE srid=(SELECT Find_SRID(?,?,?))";
				stmt = SQLUtils.prepareStatement(conn, testQuery, new String[]{ info.schema, info.table, info.column });
				rs = ((PreparedStatement)stmt).executeQuery();
		        if (rs.next())
		        	info.projection = rs.getString(1);
			}
		}
		catch (SQLException e)
		{
			if (shouldThrow)
			{
				throw new RemoteException("Unable to execute generated query:\n" + testQuery, e);
			}
			else
			{
				System.err.println("Query failed: " + testQuery);
				e.printStackTrace();
			}
		}
		finally
		{
			SQLUtils.cleanup(rs);
			SQLUtils.cleanup(stmt);
		}
	}

	private String buildFilteredColumnTitle(String columnName, Object[] filterValues)
	{
		String columnTitle = columnName + " (";
		for (int j = 0; j < filterValues.length; j++)
		{
			if (j > 0)
				columnTitle += " ";
			columnTitle += filterValues[j] == null
					? "NULL" : filterValues[j].toString();
		}
		columnTitle += ")";
		return columnTitle;
	}

	private String buildFilteredQuery(Connection conn, String unfilteredQuery, String[] columnNames)
		throws IllegalArgumentException, SQLException
	{
		String query = unfilteredQuery + " where ";
		for (int j = 0; j < columnNames.length; j++)
		{
			if (j > 0)
				query += " and ";
			
			// use case insensitive compare because that's what SELECT DISTINCT does.
			query += SQLUtils.stringCast(conn, SQLUtils.quoteSymbol(conn, columnNames[j])) + "=?";
			//query += SQLUtils.caseSensitiveCompare(conn, SQLUtils.quoteSymbol(conn, columnNames[j]), "?");
		}
		return query;
	}

	/**
	 * The following functions involve getting shapes into the database and into the config file.
	 */

	public int importSHP(
			String configConnectionName, String password, String[] fileNameWithoutExtension, String[] keyColumns,
			String sqlSchema, String sqlTablePrefix, boolean sqlOverwrite, String configTitle,
			String configKeyType, String projectionSRS, String[] nullValues, boolean importDBFData, boolean append)
		throws RemoteException
	{
		ConnectionInfo connInfo = getConnectionInfo(configConnectionName, password);
		DataConfig dataConfig = getDataConfig();
		
		if (Strings.isEmpty(sqlSchema))
			throw new RemoteException("SQL schema must be specified.");
		if (Strings.isEmpty(sqlTablePrefix))
			throw new RemoteException("SQL table prefix must be specified.");
		
		// use lower case sql table names (fix for mysql linux problems)
		sqlTablePrefix = sqlTablePrefix.toLowerCase();

		if (sqlOverwrite && !connInfo.is_superuser)
			throw new RemoteException(String.format(
					"User \"%s\" does not have permission to overwrite SQL tables.", configConnectionName));

		String dbfTableName = sqlTablePrefix + "_dbfdata";
		Connection conn = null;
        int tableId = -1;
		try
		{
			conn = connInfo.getConnection();
			// store dbf data to database
			if (importDBFData)
			{
				importDBF(
						configConnectionName, password, fileNameWithoutExtension, sqlSchema, dbfTableName,
						sqlOverwrite, nullValues);
			}

			GeometryStreamConverter converter = new GeometryStreamConverter(new SQLGeometryStreamDestination(
					conn, sqlSchema, sqlTablePrefix, sqlOverwrite));
			for (String file : fileNameWithoutExtension)
			{
				// convert shape data to streaming sql format
				String shpfile = getUploadPath() + file + ".shp";
				SHPGeometryStreamUtils.convertShapefile(converter, shpfile, Arrays.asList(keyColumns));
			}
			converter.flushAndCommitAll();
		}
		catch (Exception e)
		{
			e.printStackTrace();
			throw new RemoteException("Shapefile import failed", e);
		}
		finally
		{
			SQLUtils.cleanup(conn);
		}

        DataEntityMetadata tableInfo = new DataEntityMetadata();
        tableInfo.setPrivateMetadata(
        	PrivateMetadata.IMPORTMETHOD, "importSHP",
        	PrivateMetadata.FILENAME, CSVParser.defaultParser.createCSVRow(fileNameWithoutExtension, true),
        	PrivateMetadata.KEYCOLUMN, CSVParser.defaultParser.createCSVRow(keyColumns, true),
        	PrivateMetadata.CONNECTION, configConnectionName,
        	PrivateMetadata.SQLSCHEMA, sqlSchema,
        	PrivateMetadata.SQLTABLEPREFIX, sqlTablePrefix
        );
		
		if (importDBFData)
		{
			
			// get key column SQL code
			String keyColumnsString;
			if (keyColumns.length == 1)
			{
				keyColumnsString = keyColumns[0];
			}
			else
			{
				keyColumnsString = "CONCAT(";
				for (int i = 0; i < keyColumns.length; i++)
				{
					if (i > 0)
						keyColumnsString += ",";
					keyColumnsString += "CAST(" + keyColumns[i] + " AS CHAR)";
				}
				keyColumnsString += ")";
			}

			// add SQL statements to sqlconfig
			String[] columnNames = getSQLColumnNames(configConnectionName, password, sqlSchema, dbfTableName);
			tableId = addConfigDataTable(
					configTitle, configConnectionName,
					configKeyType, keyColumnsString, -1, columnNames, columnNames,
					sqlSchema, dbfTableName, false, null, tableInfo, append);
		}
		else
		{
			tableInfo.setPublicMetadata(
				PublicMetadata.ENTITYTYPE, EntityType.TABLE,
				PublicMetadata.TITLE, configTitle
			);
            tableId = dataConfig.newEntity(tableInfo, DataConfig.NULL, DataConfig.NULL);
		}

		try
		{
			// prepare metadata for existing column check
			DataEntityMetadata geomInfo = new DataEntityMetadata();
			geomInfo.setPublicMetadata(
					PublicMetadata.ENTITYTYPE, EntityType.COLUMN,
					PublicMetadata.DATATYPE, DataType.GEOMETRY
			);
			geomInfo.setPrivateMetadata(
				PrivateMetadata.CONNECTION, configConnectionName,
				PrivateMetadata.SQLSCHEMA, sqlSchema,
				PrivateMetadata.SQLTABLEPREFIX, sqlTablePrefix
			);
			
			// check for existing column
			int existingGeomId = ListUtils.getFirstSortedItem(
					dataConfig.getEntityIds(geomInfo),
					DataConfig.NULL
				);
			if (existingGeomId != DataConfig.NULL)
			{
				// see if the existing geometry column has the same parent table
				boolean foundSameTableId = false;
				for (int parentId : dataConfig.getParentIds(Arrays.asList(existingGeomId)))
					if (parentId == tableId)
						foundSameTableId = true;
				// if it does not have the same parent table, clear the existingGeomId
				// so a new column entity will be created under the new table
				if (!foundSameTableId)
					existingGeomId = DataConfig.NULL;
			}
			
			// set the rest of the metadata
			geomInfo.setPublicMetadata(
					PublicMetadata.KEYTYPE, configKeyType,
					PublicMetadata.PROJECTION, projectionSRS
			);
			
			if (existingGeomId == DataConfig.NULL)
			{
				// only update title if column doesn't already exist
				geomInfo.setPublicMetadata(PublicMetadata.TITLE, configTitle);
				// create new column
				dataConfig.newEntity(geomInfo, tableId, 0);
			}
			else
			{
				// update existing column
				dataConfig.updateEntity(existingGeomId, geomInfo);
			}
		}
		catch (IOException e)
		{
			throw new RemoteException("Unexpected error",e);
		}

		return tableId;
	}

	public void importDBF(
			String configConnectionName, String password, String[] fileNameWithoutExtension, String sqlSchema,
			String sqlTableName, boolean sqlOverwrite, String[] nullValues)
		throws RemoteException
	{
		ConnectionInfo info = getConnectionInfo(configConnectionName, password);
		
		if (Strings.isEmpty(sqlSchema))
			throw new RemoteException("Schema must be specified.");
		
		// use lower case sql table names (fix for mysql linux problems)
		sqlTableName = sqlTableName.toLowerCase();

		if (sqlOverwrite && !info.is_superuser)
			throw new RemoteException(String.format(
					"User \"%s\" does not have permission to overwrite SQL tables.", configConnectionName));

		Connection conn = null;
		try
		{
			conn = info.getConnection();
			File[] files = new File[fileNameWithoutExtension.length];
			for (int i = 0; i < files.length; i++)
				files[i] = new File(getUploadPath() + fileNameWithoutExtension[i] + ".dbf");

			DBFUtils.storeAttributes(files, conn, sqlSchema, sqlTableName, sqlOverwrite, nullValues);
		}
		catch (Exception e)
		{
			e.printStackTrace();
			throw new RemoteException("DBF import failed", e);
		}
		finally
		{
			SQLUtils.cleanup(conn);
		}
	}
	
	//////////////////////
	// SQL query testing

	/**
	 * Returns the results of testing attribute column sql queries.
	 */
	public DataEntity[] testAllQueries(String user, String password, int table_id)
		throws RemoteException
	{
		authenticate(user, password);
		DataConfig config = getDataConfig();
		Collection<Integer> ids = config.getChildIds(table_id);
		DataEntity[] columns = config.getEntities(ids).toArray(new DataEntity[0]);
		String query = null;
		for (DataEntity entity : columns)
		{
			try
			{
				query = entity.privateMetadata.get(PrivateMetadata.SQLQUERY);
				String connName = entity.privateMetadata.get(PrivateMetadata.CONNECTION);
				String sqlParams = entity.privateMetadata.get(PrivateMetadata.SQLPARAMS);
				SQLResult result;
				Connection conn = getConnectionConfig().getConnectionInfo(connName).getStaticReadOnlyConnection();

				String[] sqlParamsArray = null;
				if (!Strings.isEmpty(sqlParams))
					sqlParamsArray = CSVParser.defaultParser.parseCSV(sqlParams, true)[0];
				
				result = SQLUtils.getResultFromQuery(conn, query, sqlParamsArray, false);

				entity.setPrivateMetadata(PrivateMetadata.SQLRESULT, String.format("Returned %s rows", result.rows.length));
			}
			catch (Exception e)
			{
				System.err.println(query);
				e.printStackTrace();
				entity.setPrivateMetadata(PrivateMetadata.SQLRESULT, e.getMessage());
			}
		}
		return columns;
	}

	//////////////////
	// Miscellaneous

	public String[] getKeyTypes()
		throws RemoteException
	{
		List<String> list = new ArrayList<String>(getDataConfig().getUniquePublicValues(PublicMetadata.KEYTYPE));
		Collections.sort(list, String.CASE_INSENSITIVE_ORDER);
		return list.toArray(new String[0]);
	}
}
