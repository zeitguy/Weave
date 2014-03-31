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

package weave.config;

import java.rmi.RemoteException;
import java.security.InvalidParameterException;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import weave.config.ConnectionConfig.DatabaseConfigInfo;
import weave.config.tables.HierarchyTable;
import weave.config.tables.MetadataTable;
import weave.utils.ListUtils;
import weave.utils.MapUtils;
import weave.utils.SQLUtils;
import weave.utils.Strings;


/**
 * DatabaseConfig This class reads from an SQL database and provides an interface to retrieve strings.
 * 
 * @author Philip Kovac
 * @author Andy Dufilie
 */
public class DataConfig
{
	/**
	 * This is a recommended maximum number of entities a remote user should be able to request at a time.
	 */
	public static final int MAX_ENTITY_REQUEST_COUNT = 1000;

	static private final String SUFFIX_META_PRIVATE = "_meta_private";
	static private final String SUFFIX_META_PUBLIC = "_meta_public";
	static private final String SUFFIX_HIERARCHY = "_hierarchy";
	
	static public final int NULL = -1;

	private MetadataTable public_metadata;
	private MetadataTable private_metadata;
	private HierarchyTable hierarchy;
	private ConnectionConfig connectionConfig;
	private long lastModified = -1L;

	public DataConfig(ConnectionConfig connectionConfig) throws RemoteException
	{
		this.connectionConfig = connectionConfig;
		detectChange();
//		if (connectionConfig.migrationPending())
//			deleteTables();
	}
	
	@SuppressWarnings("deprecation")
	private void detectChange() throws RemoteException
	{
		long lastMod = connectionConfig.getLastModified();
		if (this.lastModified < lastMod)
		{
			if (!connectionConfig.allowDataConfigInitialize())
				throw new RemoteException("The Weave server has not been initialized yet.  Please run the Admin Console before continuing.");
			
			try
			{
				// test the connection now so it will throw an exception if there is a problem.
				Connection conn = connectionConfig.getAdminConnection();
				
				// attempt to create the schema and tables to store the configuration.
				DatabaseConfigInfo dbInfo = connectionConfig.getDatabaseConfigInfo();
				try
				{
					SQLUtils.createSchema(conn, dbInfo.schema);
				}
				catch (Exception e)
				{
					// do nothing if schema creation fails -- this is a temporary workaround for postgresql issue
					// e.printStackTrace();
				}
				
				// init SQL tables
				String tablePrefix = "weave";
				String table_meta_private = tablePrefix + SUFFIX_META_PRIVATE;
				String table_meta_public = tablePrefix + SUFFIX_META_PUBLIC;
				String table_hierarchy = tablePrefix + SUFFIX_HIERARCHY;

				hierarchy = new HierarchyTable(connectionConfig, dbInfo.schema, table_hierarchy);
				public_metadata = new MetadataTable(connectionConfig, dbInfo.schema, table_meta_public, PublicMetadata.ENTITYTYPE);
				private_metadata = new MetadataTable(connectionConfig, dbInfo.schema, table_meta_private, null);
				
				weave.config.DeprecatedConfig.migrateManifestData(conn, dbInfo.schema, table_meta_public);
			}
			catch (SQLException e)
			{
				throw new RemoteException("Unable to initialize DataConfig", e);
			}
			
			this.lastModified = lastMod;
		}
	}
	
	public boolean isEmpty() throws RemoteException
	{
		detectChange();
		return public_metadata.isEmpty() && private_metadata.isEmpty();
	}

//	private void deleteTables() throws RemoteException
//	{
//		String tablePrefix = "weave";
//		String table_meta_private = tablePrefix + SUFFIX_META_PRIVATE;
//		String table_meta_public = tablePrefix + SUFFIX_META_PUBLIC;
//		String table_hierarchy = tablePrefix + SUFFIX_HIERARCHY;
//		
//		try
//		{
//			Connection conn = connectionConfig.getAdminConnection();
//			DatabaseConfigInfo dbInfo = connectionConfig.getDatabaseConfigInfo();
//			SQLUtils.dropTableIfExists(conn, dbInfo.schema, table_meta_private);
//			SQLUtils.dropTableIfExists(conn, dbInfo.schema, table_meta_public);
//			SQLUtils.dropTableIfExists(conn, dbInfo.schema, table_hierarchy);
//		}
//		catch (SQLException e)
//		{
//			throw new RemoteException("deleteTables() failed", e);
//		}
//		
//		lastModified = -1L;
//		detectChange();
//	}
	
    public void flushInserts() throws RemoteException
    {
    	detectChange();
        try 
        {
        	hierarchy.flushInserts();
        	public_metadata.flushInserts();
            private_metadata.flushInserts();
        }
        catch (SQLException e)
        {
            throw new RemoteException("Failed flushing inserts.", e);
        }
    }
    
    /**
     * Creates a new entity and adds it as a child of another entity.
     * @param properties Metadata for the new entity.
     * @param parent_id The ID of the parent entity to which the new entity should be added as a child, or NULL for no parent.
     * @param insert_at_index The new entity's child index, or NULL to add it to the end.
     * @return The new entity's ID.
     * @throws RemoteException
     */
    public int newEntity(DataEntityMetadata properties, int parent_id, int insert_at_index) throws RemoteException
    {
    	detectChange();
    	
    	properties.notNull();
    	
    	if (!connectionConfig.migrationPending())
    	{
	    	String parentType = getEntityType(parent_id);
	    	String childType = properties.publicMetadata.get(PublicMetadata.ENTITYTYPE);
	    	if (!DataEntity.parentChildRelationshipAllowed(parentType, childType))
	    	{
	    		throw new RemoteException(String.format(
	    				"Invalid parent-child relationship (parent#%s=%s, child=%s).",
	    				parent_id,
	    				parentType,
	    				childType
	    			));
	    	}
    	}
    	
        int id = public_metadata.setProperties(NULL, properties.publicMetadata);
    	private_metadata.setProperties(id, properties.privateMetadata);
    	
        if (parent_id != NULL)
        	hierarchy.addChild(parent_id, id, insert_at_index);
        return id;
    }
    
    /**
     * Removes entities.
     * @param ids A list of IDs specifying entities to remove.
     * @return A collection of IDs that were removed.
     * @throws RemoteException
     */
    public Collection<Integer> removeEntities(Collection<Integer> ids) throws RemoteException
    {
    	detectChange();
    	Collection<Integer> removed = new HashSet<Integer>(ids);
    	Map<Integer, String> entityTypes = getEntityTypes(ids);
    	Set<Integer> childIdsToRemove = new HashSet<Integer>();
    	for (int id : ids)
    	{
    		if (Strings.equal(entityTypes.get(id), EntityType.TABLE))
	        {
	        	// remove all children from table
	        	childIdsToRemove.addAll( getChildIds(id) );
	        }
	        else // not a table
	        {
	        	// remove only non-column children
	        	Map<Integer,String> childTypes = getEntityTypes(getChildIds(id));
	        	for (int childId : childTypes.keySet())
	        		if (!Strings.equal(childTypes.get(childId), EntityType.COLUMN))
	        			childIdsToRemove.add(childId);
	        }
	        
	        hierarchy.purge(id);
	        public_metadata.removeAllProperties(id);
	        private_metadata.removeAllProperties(id);
    	}
    	
    	if (childIdsToRemove.size() > 0)
    		removed.addAll( removeEntities(childIdsToRemove) );
    	
    	return removed;
    }
    /**
	 * @param id The id of an existing entity.
	 * @param diff The properties to set.
     */
    public void updateEntity(int id, DataEntityMetadata diff) throws RemoteException
    {
    	if (id == NULL)
    		throw new RemoteException("id parameter cannot be " + NULL);
    	detectChange();
    	if (Strings.isEmpty(getEntityType(id)))
    	{
    		if (diff.publicMetadata == null || Strings.isEmpty(diff.publicMetadata.get(PublicMetadata.ENTITYTYPE)))
	    		throw new RemoteException("Unable to update entity #" + id + " because it does not exist.");
    	}
    	public_metadata.setProperties(id, diff.publicMetadata);
    	private_metadata.setProperties(id, diff.privateMetadata);
    }
    public Collection<Integer> getEntityIds(DataEntitySearchCriteria query) throws RemoteException
    {
    	detectChange();
        Set<Integer> idsMatchingPublicMetadata = null;
        Set<Integer> idsMatchingPrivateMetadata = null;
        boolean filterPublic = query != null && query.publicMetadata != null && query.publicMetadata.size() > 0;
        boolean filterPrivate = query != null && query.privateMetadata != null && query.privateMetadata.size() > 0;
        boolean noFiltering = !filterPublic && !filterPrivate;
        Collection<Integer> ids = null;

        if (filterPublic || noFiltering)
        {
        	Set<String> wf = null;
        	if (query.publicWildcardFields != null)
        		wf = new HashSet<String>(Arrays.asList(query.publicWildcardFields));
            idsMatchingPublicMetadata = public_metadata.filter(query.publicMetadata, wf);
        }
        if (filterPrivate || noFiltering)
        {
        	Set<String> wf = null;
        	if (query.privateWildcardFields != null)
        		wf = new HashSet<String>(Arrays.asList(query.privateWildcardFields));
            idsMatchingPrivateMetadata = private_metadata.filter(query.privateMetadata, wf);
        }
        if ((idsMatchingPublicMetadata != null) && (idsMatchingPrivateMetadata != null))
        {
        	if (noFiltering) // union
        		idsMatchingPublicMetadata.addAll(idsMatchingPrivateMetadata);
        	else // intersection
        		idsMatchingPublicMetadata.retainAll(idsMatchingPrivateMetadata);
            ids = idsMatchingPublicMetadata;
        }
        else if (idsMatchingPublicMetadata != null)
            ids = idsMatchingPublicMetadata;
        else if (idsMatchingPrivateMetadata != null)
            ids = idsMatchingPrivateMetadata;

        if (ids == null || ids.size() < 1)
            return Collections.emptyList();

        return ids;
    }
    
    public DataEntity getEntity(int id) throws RemoteException
    {
    	detectChange();
    	for (DataEntity result : getEntities(Arrays.asList(id)))
    		return result;
    	return null;
    }
    
    /**
     * @param ids A collection of entity ids.
     * @return A collection of DataEntity objects for the entities in the supplied list of ids that actually exist.
     */
    public Collection<DataEntity> getEntities(Collection<Integer> ids) throws RemoteException
    {
    	detectChange();
        List<DataEntity> results = new LinkedList<DataEntity>();
        Map<Integer,Map<String,String>> publicresults = public_metadata.getProperties(ids);
        
        // only proceed with the ids that actually exist
        ids = publicresults.keySet();

        Map<Integer,Map<String,String>> privateresults = private_metadata.getProperties(ids);
        for (int id : ids)
        {
            DataEntity entity = new DataEntity();
            entity.id = id;
            entity.publicMetadata = publicresults.get(id);
            entity.privateMetadata = privateresults.get(id);
            entity.notNull();
            results.add(entity);
        }
        return results;
    }
    
    /**
     * Adds a copy of an existing child to a parent.
     * @param parentId An existing parent to add a child hierarchy to.
     * @param childId An existing child to copy the hierarchy of.
     * @param insertAtIndex Identifies a child of the parent to insert the new child before.
	 * @return A collection of IDs whose relationships have changed as a result of modifying the hierarchy.
     * @throws RemoteException
     */
    public Collection<Integer> buildHierarchy(int parentId, int childId, int insertAtIndex) throws RemoteException
    {
    	detectChange();
    	return buildHierarchy(parentId, childId, insertAtIndex, new HashSet<Integer>());
    }
    
    /**
     * @private
     * @see #buildHierarchy(int, int, int)
     */
    private Collection<Integer> buildHierarchy(int parentId, int childId, int insertAtIndex, Set<Integer> ignoreList) throws RemoteException
    {
    	// prevent infinite recursion
    	if (ignoreList.contains(childId))
    		return Collections.emptySet();
		
    	Set<Integer> affectedIds = new HashSet<Integer>();
		int newChildId;
		Map<Integer,String> types = getEntityTypes(Arrays.asList(parentId, childId));
		String parentType = types.get(parentId);
		String childType = types.get(childId);
		RelationshipList childRelationships = hierarchy.getRelationships(Arrays.asList(childId));
		
		//boolean isTable = Strings.equal(childType, EntityType.TABLE);
		boolean isColumn = Strings.equal(childType, EntityType.COLUMN);
		boolean isHierarchy = Strings.equal(childType, EntityType.HIERARCHY);
		boolean isCategory = Strings.equal(childType, EntityType.CATEGORY);
		boolean isOrphan = childRelationships.getParentIds(childId).isEmpty();

		if (Strings.equal(parentType, EntityType.COLUMN))
		{
			throw new RemoteException("Cannot add children to a column entity.");
		}
		else if (parentId == NULL) // parent is root
		{
			if (isColumn) // root > column
			{
				// create a new blank hierarchy to contain the child
				DataEntityMetadata metadata = new DataEntityMetadata();
				metadata.setPublicMetadata(PublicMetadata.ENTITYTYPE, EntityType.HIERARCHY);
				parentId = newEntity(metadata, NULL, NULL);
				// recursive call with new parent id
				return buildHierarchy(parentId, childId, NULL, ignoreList);
			}
			else if (isHierarchy) // root > hierarchy
			{
				// hierarchies are always at root, so do nothing.
				return Collections.emptySet();
			}
			else if (isOrphan && isCategory) // root > category
			{
				// ok to convert orphan category to hierarchy
				newChildId = childId;
				// update entityType to hierarchy
				DataEntityMetadata metadata = new DataEntityMetadata();
				metadata.setPublicMetadata(PublicMetadata.ENTITYTYPE, EntityType.HIERARCHY);
				updateEntity(childId, metadata);
			}
			else // root > non-column
			{
				// copy the child as a hierarchy
				DataEntityMetadata metadata = getEntity(childId);
				metadata.setPublicMetadata(PublicMetadata.ENTITYTYPE, EntityType.HIERARCHY);
				newChildId = newEntity(metadata, NULL, NULL);
			}
		}
		else // parent is non-column non-root
        {
			if (isColumn) // add child column
			{
				// columns can be added directly to new parents
				newChildId = childId;
			}
			else if (isOrphan && isCategory) // add child orphan category
			{
				// ok to use orphan category
				newChildId = childId;
			}
			else // add child non-column
			{
				// copy as a new category
				DataEntityMetadata metadata = getEntity(childId);
				metadata.setPublicMetadata(PublicMetadata.ENTITYTYPE, EntityType.CATEGORY);
				newChildId = newEntity(metadata, parentId, insertAtIndex);
			}
		}
		
		if (newChildId != childId)
		{
			// prevent infinite recursion
			ignoreList.add(newChildId);
			// recursively copy each child hierarchy element
			for (int grandChildId : childRelationships.getChildIds(childId))
				if (grandChildId != newChildId)
					affectedIds.addAll( buildHierarchy(newChildId, grandChildId, NULL, ignoreList) );
		}
		
		// add new child to parent
		affectedIds.add(newChildId);
		if (parentId != NULL)
		{
			affectedIds.add(parentId);
			hierarchy.addChild(parentId, newChildId, insertAtIndex);
		}
		return affectedIds;
    }
    
    public void removeChild(int parent_id, int child_id) throws RemoteException
    {
    	detectChange();
        if (Strings.equal(getEntityType(parent_id), EntityType.TABLE))
        {
            throw new RemoteException("Can't remove children from a datatable.", null);
        }
        hierarchy.removeChild(parent_id, child_id);
    }
    
    public Map<Integer,String> getEntityTypes(Collection<Integer> ids) throws RemoteException
    {
    	return public_metadata.getPropertyMap(ids, PublicMetadata.ENTITYTYPE);
    }
    
    private String getEntityType(int entityId) throws RemoteException
    {
    	return getEntityTypes(Arrays.asList(entityId)).get(entityId);
    }
    
    /**
     * Shortcut for getRelationships(Arrays.asList(id)).getParentIds(id).
     * If you need this information for multiple IDs, use getRelationships() instead.
     * @see #getRelationships(Collection)
     */
    public List<Integer> getParentIds(int id) throws RemoteException
    {
    	return getRelationships(Arrays.asList(id)).getParentIds(id);
    }
    
    /**
     * Shortcut for getRelationships(Arrays.asList(id)).getChildIds(id).
     * If you need this information for multiple IDs, use getRelationships() instead.
     * @see #getRelationships(Collection)
     */
    public List<Integer> getChildIds(int id) throws RemoteException
    {
    	return getRelationships(Arrays.asList(id)).getChildIds(id);
    }
    
	/**
	 * Gets a list of parent-child relationships for a set of entities.
	 * @param ids A collection of entity IDs.
	 * @return An ordered list of parent-child relationships involving the specified entities.
	 */
    public RelationshipList getRelationships(Collection<Integer> ids) throws RemoteException
    {
    	detectChange();
    	return hierarchy.getRelationships(ids);
    }
    
    public Collection<String> getUniquePublicValues(String property) throws RemoteException
    {
    	detectChange();
    	return new HashSet<String>(public_metadata.getPropertyMap(null, property).values());
    }
    
    public EntityHierarchyInfo[] getEntityHierarchyInfo(Map<String,String> publicMetadata) throws RemoteException
    {
    	detectChange();
    	Collection<Integer> ids = public_metadata.filter(publicMetadata, null);
    	EntityHierarchyInfo[] result = new EntityHierarchyInfo[ids.size()];
    	if (result.length == 0)
    		return result;
    	
    	Map<Integer,Integer> childCounts = hierarchy.getChildCounts(ids);
    	Map<Integer,String> titles = public_metadata.getPropertyMap(ids, PublicMetadata.TITLE);
    	int i = 0;
    	for (Integer id : ids)
    	{
    		EntityHierarchyInfo info = new EntityHierarchyInfo();
    		info.id = id;
    		info.title = titles.get(id);
    		info.numChildren = childCounts.containsKey(id) ? childCounts.get(id) : 0;
    		result[i++] = info;
    	}
    	Arrays.sort(result, EntityHierarchyInfo.SORT_BY_TITLE);
    	return result;
    }
    
    

    
    
    
    
    
    
    
    
    
    
    ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////
    
    
    
	static public class PrivateMetadata
	{
		static public final String CONNECTION = "connection"; // required to retrieve data from sql, not visible to client
		static public final String SQLSCHEMA = "sqlSchema";
		static public final String SQLTABLE = "sqlTable";
		static public final String SQLCOLUMN = "sqlColumn";
		static public final String SQLFILTERCOLUMNS = "sqlFilterColumns";
		static public final String SQLQUERY = "sqlQuery"; // required to retrieve data from sql, not visible to client
		static public final String SQLPARAMS = "sqlParams"; // only transmitted from client to server, never stored in the database
		static public final String SQLRESULT = "sqlResult"; // only transmitted from server to client, never stored in the database
        static public final String IMPORTMETHOD = "importMethod";
        static public final String SQLKEYCOLUMN = "sqlKeyColumn";
		static public final String SQLTABLEPREFIX = "sqlTablePrefix"; // used for geometry column
		static public final String FILENAME = "fileName";
		static public final String KEYCOLUMN = "keyColumn";
	}
	
	static public class PublicMetadata
	{
		static public final String ENTITYTYPE = "entityType";
		static public final String TITLE = "title";
		static public final String KEYTYPE = "keyType";
		static public final String DATATYPE = "dataType";
		static public final String PROJECTION = "projection";
		static public final String MIN = "min";
		static public final String MAX = "max";
		static public final String NUMBER = "number";
		static public final String STRING = "string";
	}
	
	static public class EntityType
	{
		public static final String TABLE = "table";
		public static final String COLUMN = "column";
		public static final String HIERARCHY = "hierarchy";
		public static final String CATEGORY = "category";
		
		@Deprecated public static String fromInt(int type)
		{
			switch (type)
			{
				case NULL: return "UNSPECIFIED";
				case 0: return TABLE;
				case 1: return COLUMN;
				case 2: return HIERARCHY;
				case 3: return CATEGORY;
			}
			throw new InvalidParameterException("Invalid type: " + type);
		}
	}
	
	static public class DataType
	{
		static public final String NUMBER = "number";
		static public final String STRING = "string";
		static public final String GEOMETRY = "geometry";
		
		/**
		 * This function determines the corresponding DataType constant for a SQL type defined in java.sql.Types.
		 * @param sqlType A SQL data type defined in java.sql.Types.
		 * @return The corresponding constant NUMBER or STRING or GEOMETRY.
		 */
		static public String fromSQLType(int sqlType)
		{
			if (SQLUtils.sqlTypeIsGeometry(sqlType))
				return GEOMETRY;
			else if (SQLUtils.sqlTypeIsNumeric(sqlType))
				return NUMBER;
			else
				return STRING;
		}
	}
	
	static public class DataEntitySearchCriteria extends DataEntityMetadata
	{
		/**
		 * A list of field names in publicMetadata that should be treated
		 * as search strings with wildcards '?' and '*' for single-character
		 * and multi-character matching, respectively.
		 */
		public String[] publicWildcardFields = null;
		/**
		 * A list of field names in privateMetadata that should be treated
		 * as search strings with wildcards '?' and '*' for single-character
		 * and multi-character matching, respectively.
		 */
		public String[] privateWildcardFields = null;
		
		public String toString()
		{
			return MapUtils.fromPairs(
					"publicMetadata", publicMetadata,
					"privateMetadata", privateMetadata,
					"publicWildcardFields", Arrays.deepToString(publicWildcardFields),
					"privateWildcardFields", Arrays.deepToString(privateWildcardFields)
				).toString();
		}
	}
	
	/**
	 * This class contains public and private metadata for an entity.
	 */
	static public class DataEntityMetadata
	{
		/**
		 * Private metadata, mapping field names to values.
		 */
		public Map<String,String> privateMetadata = new HashMap<String, String>();
		/**
		 * Public metadata, mapping field names to values.
		 */
		public Map<String,String> publicMetadata = new HashMap<String, String>();
		
		/**
		 * Makes sure privateMetadata and publicMetadata are not null.
		 */
		public void notNull()
		{
			if (privateMetadata == null)
				privateMetadata = new HashMap<String, String>();
			if (publicMetadata == null)
				publicMetadata = new HashMap<String, String>();
		}
		
		/**
		 * @param pairs A list of Key-value pairs, like [key1,value1,key2,value2,...]
		 */
		public void setPublicMetadata(String ...pairs)
		{
			MapUtils.putPairs(publicMetadata, (Object[])pairs);
		}
		
		/**
		 * @param pairs A list of Key-value pairs, like [key1,value1,key2,value2,...]
		 */
		public void setPrivateMetadata(String ...pairs)
		{
			MapUtils.putPairs(privateMetadata, (Object[])pairs);
		}
		
		public String toString()
		{
			return MapUtils.fromPairs(
					"publicMetadata", publicMetadata,
					"privateMetadata", privateMetadata
				).toString();
		}
	}
	
	/**
	 * Represents a parent-child relationship between two entities.
	 */
	public static class Relationship
	{
		public Relationship() { }
		public Relationship(int parentId, int childId)
		{
			this.parentId = parentId;
			this.childId = childId;
		}
		public int parentId;
		public int childId;
		
		public String toString()
		{
			return String.format("%s>%s", parentId, childId);
		}
	}
	
	/**
	 * An ordered List of Relationship objects which adds two functions: getChildIds() and getParentIds().
	 */
	public static class RelationshipList extends LinkedList<Relationship>
	{
		private static final long serialVersionUID = 1L;
		/**
		 * Gets an ordered list of child IDs for a specified parent.
		 * @param parentId A parent entity ID.
		 * @return An ordered list of child entity IDs.
		 */
		public List<Integer> getChildIds(int parentId)
		{
			List<Integer> ids = new LinkedList<Integer>();
			for (Relationship r : this)
				if (r.parentId == parentId)
					ids.add(r.childId);
			return ids;
		}
		/**
		 * Gets a list of IDs for parents having a specified child.
		 * @param childId A child entity ID.
		 * @return A list of parent entity IDs.
		 */
		public List<Integer> getParentIds(int childId)
		{
			List<Integer> ids = new LinkedList<Integer>();
			for (Relationship r : this)
				if (r.childId == childId)
					ids.add(r.parentId);
			return ids;
		}
	}

	static public class DataEntityWithRelationships extends DataEntity
	{
		public int[] parentIds;
		public int[] childIds;
		
		public DataEntityWithRelationships() { }
		
		public DataEntityWithRelationships(DataEntity base, List<Relationship> relationships)
		{
			if (base != null)
			{
				this.id = base.id;
				this.publicMetadata = base.publicMetadata;
				this.privateMetadata = base.privateMetadata;
			}
			
			List<Integer> parentIds = new LinkedList<Integer>();
			List<Integer> childIds = new LinkedList<Integer>();
			for (Relationship r : relationships)
			{
				if (id == r.childId)
					parentIds.add(r.parentId);
				else if (id == r.parentId)
					childIds.add(r.childId);
			}
			
			this.parentIds = ListUtils.toIntArray(parentIds);
			this.childIds = ListUtils.toIntArray(childIds);
		}
		
		public String toString()
		{
			return String.format("(%s%s)",
					MapUtils.fromPairs(
							"childIds", Arrays.toString(childIds)
						).toString(),
					super.toString()
				);
		}
	}

	/**
	 * This class contains metadata for an attributeColumn entry.
	 */
	static public class DataEntity extends DataEntityMetadata
	{
		public int id = NULL;
		
		private static boolean equalPairs(String a1, String a2, String b1, String b2)
		{
			return Strings.equal(a1, a2) && Strings.equal(b1, b2);
		}
		
	    public static boolean parentChildRelationshipAllowed(String parentType, String childType)
	    {
	    	return (Strings.isEmpty(parentType) && Strings.equal(childType, EntityType.TABLE))
	    		|| (Strings.isEmpty(parentType) && Strings.equal(childType, EntityType.HIERARCHY))
	    		|| equalPairs(parentType, EntityType.TABLE, childType, EntityType.COLUMN)
		    	|| equalPairs(parentType, EntityType.HIERARCHY, childType, EntityType.CATEGORY)
		    	|| equalPairs(parentType, EntityType.HIERARCHY, childType, EntityType.COLUMN)
		    	|| equalPairs(parentType, EntityType.CATEGORY, childType, EntityType.CATEGORY)
		    	|| equalPairs(parentType, EntityType.CATEGORY, childType, EntityType.COLUMN);
	    }
	    
		public String toString()
		{
			return MapUtils.fromPairs(
					"id", id,
					"publicMetadata", publicMetadata,
					"privateMetadata", privateMetadata
				).toString();
		}
	}
	
	static public class EntityHierarchyInfo
	{
		public int id;
		public String title;
		public int numChildren;
		
		public static Comparator<EntityHierarchyInfo> SORT_BY_TITLE = new Comparator<EntityHierarchyInfo>()
		{
			public int compare(EntityHierarchyInfo o1, EntityHierarchyInfo o2)
			{
				// special cases for null values to prevent null pointer errors
				if (o1.title == null)
					return -1;
				if (o2.title == null)
					return 1;
				if (o1 == o2)
					return 0;
				return String.CASE_INSENSITIVE_ORDER.compare(o1.title, o2.title);
			}
		};
	}
}
