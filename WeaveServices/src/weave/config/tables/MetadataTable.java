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

package weave.config.tables;

import java.rmi.RemoteException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;
import java.util.Vector;

import weave.config.ConnectionConfig;
import weave.config.DataConfig;
import weave.utils.MapUtils;
import weave.utils.SQLExceptionWithQuery;
import weave.utils.SQLResult;
import weave.utils.SQLUtils;
import weave.utils.SQLUtils.WhereClause;
import weave.utils.Strings;


/**
 * @author Philip Kovac
 * @author Andy Dufilie
 */
public class MetadataTable extends AbstractTable
{
	public static final String FIELD_ID = "entity_id";
	public static final String FIELD_NAME = "meta_name";
	public static final String FIELD_VALUE = "meta_value";
	
	private static final Set<String> caseSensitiveFields = new HashSet<String>(Arrays.asList(FIELD_NAME, FIELD_VALUE));
	
	private final String requiredMetadataName;
	
	/**
	 * @param connectionConfig
	 * @param schemaName
	 * @param tableName
	 * @param requiredMetadataName The name of a metadata field that is required for entities.
	 */
	public MetadataTable(ConnectionConfig connectionConfig, String schemaName, String tableName, String requiredMetadataName) throws RemoteException
	{
		super(connectionConfig, schemaName, tableName, FIELD_ID, FIELD_NAME, FIELD_VALUE);
		this.requiredMetadataName = requiredMetadataName;
		initTable();
	}
	
	protected void initTable() throws RemoteException
	{
		Connection conn;
		
		try
		{
			conn = connectionConfig.getAdminConnection();
			
			if (!tableExists())
			{
				// primary key is (id,property) for indexing and because
				// we don't want duplicate properties for the same id
				SQLUtils.createTable(
					conn, schemaName, tableName,
					Arrays.asList(fieldNames),
					Arrays.asList(
						SQLUtils.getBigIntTypeString(conn),
						SQLUtils.getVarcharTypeString(conn, 255),
						SQLUtils.getVarcharTypeString(conn, 2048)
					),
					Arrays.asList(FIELD_ID, FIELD_NAME)
				);
				
				/* Index of (property) */
				SQLUtils.createIndex(
						conn, schemaName, tableName,
						new String[]{FIELD_NAME},
						null
				);
				/* Index of (Property, Value), important for finding ids with metadata criteria */
				SQLUtils.createIndex(
						conn, schemaName, tableName,
						new String[]{FIELD_NAME, FIELD_VALUE},
						new Integer[]{32,32}
				);
			}
		} 
		catch (SQLException e)
		{
			throw new RemoteException("Unable to initialize metadata table.", e);
		}
	}
    
	/**
	 * @param id Either the id of an existing entity or -1 to create a new one.
	 * @param diff The properties to set.
	 * @return The id that was specified, or the id of a new entity if id was specified as DataConfig.NULL.
	 */
	public int setProperties(int id, Map<String,String> diff) throws RemoteException
	{
		try
		{
			Map<String,Object> record;
			boolean newId = (id == DataConfig.NULL);
			
			if (connectionConfig.migrationPending())
			{
				if (newId)
					throw new RemoteException("id cannot be unspecified during migration");
			}
			else
			{
				// remove any existing values for the specified properties
				Connection conn = connectionConfig.getAdminConnection();
				
				if (newId)
				{
					if (requiredMetadataName == null)
						throw new RemoteException(String.format("The \"%s\" table cannot be used to generate new ids because it has no requiredMetadataName.", tableName));
					
					if (diff == null || Strings.isEmpty(diff.get(requiredMetadataName)))
						throw new RemoteException(String.format("Missing required metadata field \"%s\"", requiredMetadataName));
					
					record = MapUtils.fromPairs(
						FIELD_NAME, requiredMetadataName,
						FIELD_VALUE, diff.get(requiredMetadataName)
					);
					id = SQLUtils.insertRowReturnID(conn, schemaName, tableName, record, FIELD_ID);
				}
				else if (diff == null)
				{
					// do nothing
					return id;
				}
				else if (requiredMetadataName != null && diff.containsKey(requiredMetadataName) && Strings.isEmpty(diff.get(requiredMetadataName)))
				{
					throw new RemoteException(String.format("Cannot remove required metadata field \"%s\"", requiredMetadataName));
				}
				
				List<Map<String,Object>> records = new Vector<Map<String,Object>>(diff.size());
				for (String property : diff.keySet())
				{
					if (newId && property.equals(requiredMetadataName))
						continue;
					record = MapUtils.fromPairs(FIELD_ID, id, FIELD_NAME, property);
					records.add(record);
				}
				WhereClause<Object> where = new WhereClause<Object>(conn, records, caseSensitiveFields, false);
				SQLUtils.deleteRows(conn, schemaName, tableName, where);
			}
			
			for (Entry<String,String> entry : diff.entrySet())
			{
				String key = entry.getKey();
				String value = entry.getValue();
				
				if (newId && key.equals(requiredMetadataName))
					continue;
				
				// ignore null values and empty strings (has the effect of deleting the property)
				if (value != null && value.length() > 0)
					insertRecord(id, entry.getKey(), value);
			}
			
			return id;
		} 
		catch (SQLException e)
		{
			throw new RemoteException("Unable to set property.", e);
		}
	}

	public void removeAllProperties(int id) throws RemoteException
	{
		try 
		{
			Connection conn = connectionConfig.getAdminConnection();
			Map<String,Object> conditions = MapUtils.fromPairs(FIELD_ID, id);
			WhereClause<Object> where = new WhereClause<Object>(conn, conditions, caseSensitiveFields, true);
			SQLUtils.deleteRows(conn, schemaName, tableName, where);
		}
		catch (SQLException e)
		{
			throw new RemoteException("Unable to clear properties for a given id.", e);
		}
	}
	public Map<Integer, String> getPropertyMap(Collection<Integer> ids, String property) throws RemoteException
	{
		ResultSet rs = null;
		PreparedStatement stmt = null;
		String query = null;
		try
		{
			Map<Integer,String> result = new HashMap<Integer,String>();
			if (ids != null && ids.size() == 0)
				return result;
			
			Connection conn = connectionConfig.getAdminConnection();
			
			// build query
			String quotedIdField = SQLUtils.quoteSymbol(conn, FIELD_ID);
			query = String.format(
					"SELECT %s,%s FROM %s WHERE %s",
					quotedIdField,
					SQLUtils.quoteSymbol(conn, FIELD_VALUE),
					SQLUtils.quoteSchemaTable(conn, schemaName, tableName),
					SQLUtils.caseSensitiveCompare(conn, SQLUtils.quoteSymbol(conn, FIELD_NAME), "?")
				);
			if (ids != null)
				query += String.format(" AND %s IN (%s)", quotedIdField, Strings.join(",", ids));
			
			// make query and get values
			stmt = SQLUtils.prepareStatement(conn, query, Arrays.asList(property));
			rs = stmt.executeQuery();
			rs.setFetchSize(SQLResult.FETCH_SIZE);
			while (rs.next())
				result.put(rs.getInt(FIELD_ID), rs.getString(FIELD_VALUE));
			
			return result;
		}
		catch (SQLException e)
		{
			e = new SQLExceptionWithQuery(query, e);
			throw new RemoteException("Unable to get all instances of a property.", e);
		}
		finally
		{
			SQLUtils.cleanup(rs);
			SQLUtils.cleanup(stmt);
		}
	}
	public Map<Integer, Map<String,String>> getProperties(Collection<Integer> ids) throws RemoteException
	{
		PreparedStatement stmt = null;
		ResultSet rs = null;
		try
		{
			Map<Integer,Map<String,String>> result = MapUtils.fromPairs();
			
			if (ids.size() == 0)
				return result;
			
			Connection conn = connectionConfig.getAdminConnection();
			String query = String.format(
					"SELECT * FROM %s WHERE %s IN (%s)",
					SQLUtils.quoteSchemaTable(conn, schemaName, tableName),
					SQLUtils.quoteSymbol(conn, FIELD_ID),
					Strings.join(",", ids)
				);
			stmt = conn.prepareStatement(query);
			rs = stmt.executeQuery();
			rs.setFetchSize(SQLResult.FETCH_SIZE);
			while (rs.next())
			{
				int id = rs.getInt(FIELD_ID);
				String property = rs.getString(FIELD_NAME);
				String value = rs.getString(FIELD_VALUE);
				
				if (!result.containsKey(id))
					result.put(id, new HashMap<String,String>());
				
				result.get(id).put(property, value);
			}
			
			return result;
		}   
		catch (SQLException e)
		{
			throw new RemoteException("Unable to retrieve metadata", e);
		}
		finally
		{
			SQLUtils.cleanup(rs);
			SQLUtils.cleanup(stmt);
		}
	}
	/**
	 * Finds IDs of entities having metadata matching a set of constraints. 
	 * @param constraints Name-value pairs to be used as search criteria.
	 * @return A set of entity IDs.
	 */
	public Set<Integer> filter(Map<String,String> constraints) throws RemoteException
	{
		try
		{
			Connection conn = connectionConfig.getAdminConnection();
			List<Map<String,String>> crossRowArgs = new Vector<Map<String,String>>(constraints.size());

			for (Entry<String,String> keyValPair : constraints.entrySet())
			{
				if (keyValPair.getKey() == null || keyValPair.getValue() == null)
					continue;
				Map<String,String> colValPair = MapUtils.fromPairs(
					FIELD_NAME, keyValPair.getKey(),
					FIELD_VALUE, keyValPair.getValue()
				);
				crossRowArgs.add(colValPair);
			}
			return new HashSet<Integer>(SQLUtils.crossRowSelect(conn, schemaName, tableName, FIELD_ID, crossRowArgs, caseSensitiveFields));
		}
		catch (SQLException e)
		{
			throw new RemoteException("Unable to get ids given a set of property/value pairs.", e);
		}
	}
	public boolean isEmpty() throws RemoteException
	{
		String query = null;
		Statement stmt = null;
		try
		{
			Connection conn = connectionConfig.getAdminConnection();
			stmt = conn.createStatement();
			query = String.format("SELECT COUNT(*) FROM %s", SQLUtils.quoteSchemaTable(conn, schemaName, tableName));
			return SQLUtils.getSingleIntFromQuery(stmt, query, 0) > 0;
		}
		catch (SQLException cause)
		{
			throw new RemoteException("Unable to get row count", new SQLExceptionWithQuery(query, cause));
		}
		finally
		{
			SQLUtils.cleanup(stmt);
		}
	}
}
