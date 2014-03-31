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

package weave.data.DataSources
{
	import flash.net.URLRequest;
	import flash.utils.Dictionary;
	
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	import mx.utils.ObjectUtil;
	
	import weave.api.WeaveAPI;
	import weave.api.data.ColumnMetadata;
	import weave.api.data.DataTypes;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IColumnReference;
	import weave.api.data.IDataRowSource;
	import weave.api.data.IDataSource;
	import weave.api.data.IQualifiedKey;
	import weave.api.disposeObject;
	import weave.api.newLinkableChild;
	import weave.api.objectWasDisposed;
	import weave.api.registerLinkableChild;
	import weave.api.reportError;
	import weave.api.services.IWeaveGeometryTileService;
	import weave.compiler.StandardLib;
	import weave.core.LinkableString;
	import weave.core.LinkableVariable;
	import weave.data.AttributeColumns.DateColumn;
	import weave.data.AttributeColumns.GeometryColumn;
	import weave.data.AttributeColumns.NumberColumn;
	import weave.data.AttributeColumns.ProxyColumn;
	import weave.data.AttributeColumns.SecondaryKeyNumColumn;
	import weave.data.AttributeColumns.StreamedGeometryColumn;
	import weave.data.AttributeColumns.StringColumn;
	import weave.data.ColumnReferences.HierarchyColumnReference;
	import weave.data.QKeyManager;
	import weave.primitives.GeneralizedGeometry;
	import weave.services.WeaveDataServlet;
	import weave.services.addAsyncResponder;
	import weave.services.beans.AttributeColumnData;
	import weave.services.beans.EntityType;
	import weave.utils.AsyncSort;
	import weave.utils.ColumnUtils;
	import weave.utils.HierarchyUtils;
	
	/**
	 * WeaveDataSource is an interface for retrieving columns from Weave data servlets.
	 * 
	 * @author adufilie
	 */
	public class WeaveDataSource extends AbstractDataSource implements IDataRowSource
	{
		WeaveAPI.registerImplementation(IDataSource, WeaveDataSource, "Weave server");
		
		public function WeaveDataSource()
		{
			url.addImmediateCallback(this, handleURLChange, true);
		}

		public const url:LinkableString = newLinkableChild(this, LinkableString);
		public const hierarchyURL:LinkableString = newLinkableChild(this, LinkableString);
		
		/**
		 * This is an Array of public metadata field names that should be used to uniquely identify columns when querying the server.
		 */		
		public const idFields:LinkableVariable = registerLinkableChild(this, new LinkableVariable(Array, verifyStringArray));
		
		private function verifyStringArray(array:Array):Boolean
		{
			return StandardLib.getArrayType(array) == String;
		}

		public function getRows(keys:Array):AsyncToken
		{
			return dataService.getRows(keys);
		}
		/**
		 * This function prevents url.value from being null.
		 */
		private function handleURLChange():void
		{
			url.delayCallbacks();
			
			var defaultBaseURL:String = '/WeaveServices';
			var defaultServletName:String = '/DataService';
			
			var deprecatedBaseURL:String = '/OpenIndicatorsDataServices';
			if (!url.value || url.value == deprecatedBaseURL || url.value == deprecatedBaseURL + defaultServletName)
				url.value = defaultBaseURL + defaultServletName;
			
			// backwards compatibility -- if url ends in default base url, append default servlet name
			if (url.value.split('/').pop() == defaultBaseURL.split('/').pop())
				url.value += defaultServletName;
			
			// replace old dataService
			disposeObject(dataService);
			dataService = registerLinkableChild(this, new WeaveDataServlet(url.value));
			
			url.resumeCallbacks();
		}
		
		/**
		 * This gets called as a grouped callback when the session state changes.
		 */
		override protected function initialize():void
		{
			super.initialize();
		}
		
		override protected function handleHierarchyChange():void
		{
			super.handleHierarchyChange();
			_convertOldHierarchyFormat(_attributeHierarchy.value);
			_attributeHierarchy.detectChanges();
		}
		
		protected function _convertOldHierarchyFormat(root:XML):void
		{
			if (!root)
				return;
			
			convertOldHierarchyFormat(root, "category", {
				dataTableName: "name"
			});
			convertOldHierarchyFormat(root, "attribute", {
				attributeColumnName: "name",
				dataTableName: "dataTable",
				dataType: _convertOldDataType,
				projectionSRS: ColumnMetadata.PROJECTION
			});
			for each (var tag:XML in root.descendants())
			{
				if (!String(tag.@title))
				{
					var newTitle:String;
					if (String(tag.@name) && String(tag.@year))
						newTitle = String(tag.@name) + ' (' + tag.@year + ')';
					else if (String(tag.@name))
						newTitle = String(tag.@name);
					tag.@title = newTitle || 'untitled';
				}
			}
		}
		
		protected function _convertOldDataType(value:String):String
		{
			if (value == 'Geometry')
				return DataTypes.GEOMETRY;
			if (value == 'String')
				return DataTypes.STRING;
			if (value == 'Number')
				return DataTypes.NUMBER;
			return value;
		}

		override public function getAttributeColumn(columnReference:IColumnReference):IAttributeColumn
		{
			var hcr:HierarchyColumnReference = columnReference as HierarchyColumnReference;
			if (hcr)
			{
				var hash:String = columnReference.getHashCode();
				_convertOldHierarchyFormat(hcr.hierarchyPath.value);
				hcr.hierarchyPath.detectChanges();
				if (hash != columnReference.getHashCode())
					return WeaveAPI.AttributeColumnCache.getColumn(columnReference);
			}
			return super.getAttributeColumn(columnReference);
		}
		
		private var dataService:WeaveDataServlet = null;
		
		/**
		 * This function must be implemented by classes which extend AbstractDataSource.
		 * This function should make a request to the source to fill in the hierarchy.
		 * @param subtreeNode A pointer to a node in the hierarchy representing the root of the subtree to request from the source.
		 */
		override protected function requestHierarchyFromSource(subtreeNode:XML = null):void
		{
			_convertOldHierarchyFormat(subtreeNode);
			
			//trace("requestHierarchyFromSource("+(subtreeNode?attributeHierarchy.getPathFromNode(subtreeNode).toXMLString():'')+")");

			if (!subtreeNode || subtreeNode == _attributeHierarchy.value)
			{
				if (hierarchyURL.value != "" && hierarchyURL.value != null)
				{
					WeaveAPI.URLRequestUtils.getURL(this, new URLRequest(hierarchyURL.value), handleHierarchyURLDownload, handleHierarchyURLDownloadError, hierarchyURL.value);
					trace("hierarchy url "+hierarchyURL.value);
					return;
				}
				if (_attributeHierarchy.value != null)
				{
					// stop if hierarchy is defined
					return;
				}
				
				_attributeHierarchy.value = <hierarchy/>;
				
				//trace("getDataServiceMetadata()");

				// temporary solution
				
				// get all dataTables and all geometry columns
				var _tableEntities:Array = null;
				var _geometryEntities:Array = null;
				
				addAsyncResponder(
					dataService.getEntityIds({"entityType": EntityType.TABLE}),
					handleRootIds,
					handleFault,
					EntityType.TABLE
				);
				
				// get all geometry columns
				addAsyncResponder(
					dataService.getEntityIds({"dataType": DataTypes.GEOMETRY, "entityType": EntityType.COLUMN}),
					handleRootIds,
					handleFault,
					EntityType.COLUMN
				);
				
				function handleRootIds(event:ResultEvent, entityType:String):void
				{
					if (!event.result)
					{
						reportError(NO_RESULT_ERROR);
						return;
					}
					var ids:Array = event.result as Array;
					var query:AsyncToken = dataService.getEntitiesById(ids);
					addAsyncResponder(query, handleRootEntities, handleFault, [entityType, ids]);
				}
				function handleRootEntities(event:ResultEvent, entityType_entityIds:Array):void
				{
					if (!event.result)
					{
						reportError(NO_RESULT_ERROR);
						return;
					}
					var entityType:String = entityType_entityIds[0];
					var entityIds:Array = entityType_entityIds[1];
					var orderLookup:Object = createLookup(entityIds);
					
					var entities:Array = event.result as Array;
					AsyncSort.sortImmediately(
						entities,
						function(entity1:Object, entity2:Object):int
						{
							return ObjectUtil.numericCompare(orderLookup[entity1.id], orderLookup[entity2.id]);
						}
					);
					
					if (entityType == EntityType.TABLE)
						_tableEntities = entities;
					else
						_geometryEntities = entities;
					
					// only proceed when we have both
					if (!_tableEntities || !_geometryEntities)
						return;
					
					generateRootHierarchy(_tableEntities, _geometryEntities);
				}
			}
			else
			{
				var idStr:String = subtreeNode.attribute(ENTITY_ID);
				if (idStr)
				{
					addAsyncResponder(
						dataService.getEntityChildIds(int(idStr)),
						handleColumnIds,
						handleFault,
						subtreeNode
					);
				}
				else
				{
					// backwards compatibility - get columns with matching dataTable metadata
					var dataTableName:String = subtreeNode.attribute("name");
					addAsyncResponder(
						dataService.getEntityIds({"dataTable": dataTableName, "entityType": EntityType.COLUMN}),
						function(event:ResultEvent, subtreeNode:XML):void
						{
							if (!event.result)
							{
								reportError(NO_RESULT_ERROR);
								return;
							}
							var ids:Array = event.result as Array;
							addAsyncResponder(
								dataService.getParents(ids[0]),
								function(event:ResultEvent, subtreeNode:XML):void
								{
									if (!event.result)
									{
										reportError(NO_RESULT_ERROR);
										return;
									}
									var ids:Array = event.result as Array;
									addAsyncResponder(
										dataService.getEntityChildIds(ids[0]),
										handleColumnIds,
										handleFault,
										subtreeNode
									);
								},
								handleFault,
								subtreeNode
							);
						},
						handleFault,
						subtreeNode
					);
				}
				function handleColumnIds(event:ResultEvent, subtreeNode:XML):void
				{
					if (!event.result)
					{
						reportError(NO_RESULT_ERROR);
						return;
					}
					var ids:Array = event.result as Array;
					var query:AsyncToken = dataService.getEntitiesById(ids);
					addAsyncResponder(query, handleColumnEntities, handleFault, [subtreeNode, ids]);
				}
			}
		}
		
		private static const NO_RESULT_ERROR:String = "Received null result from Weave server.";
		
		/**
		 * Called when the hierarchy is downloaded from a URL.
		 */
		private function handleHierarchyURLDownload(event:ResultEvent, url:String):void
		{
			if (objectWasDisposed(this) || url != hierarchyURL.value)
				return;
			_attributeHierarchy.value = XML(event.result); // this will run callbacks
		}

		/**
		 * Called when the hierarchy fails to download from a URL.
		 */
		private function handleHierarchyURLDownloadError(event:FaultEvent, url:String):void
		{
			if (url != hierarchyURL.value)
				return;
			reportError(event, null, url);
		}
		
		public static const ENTITY_ID:String = 'weaveEntityId';
		
		private function generateRootHierarchy(tables:Array, geoms:Array):void
		{
			if (objectWasDisposed(this) || !(_attributeHierarchy.value == <hierarchy/> || !_attributeHierarchy.value))
				return;

			var tag:XML;
			var attrName:String;
			var i:int;
			var parent:XML;
			var metadata:Object;
			var entityObj:Object;

//			try
//			{
				for (i = 0; i < tables.length; i++)
				{
					metadata = tables[i].publicMetadata;
					metadata[ENTITY_ID] = tables[i].id;
					tables[i] = metadata;
				}
				
				for (i = 0; i < geoms.length; i++)
				{
					metadata = geoms[i].publicMetadata;
					metadata[ENTITY_ID] = geoms[i].id;
					geoms[i] = metadata;
				}
				
				AsyncSort.sortImmediately(tables, function(a:*, b:*):* { return AsyncSort.compareCaseInsensitive(a.title, b.title); });
				AsyncSort.sortImmediately(geoms, function(a:*, b:*):* { return AsyncSort.compareCaseInsensitive(a.title, b.title); });
	
				//trace("handleGetDataServiceMetadata",ObjectUtil.toString(event));

				if (!_attributeHierarchy.value)
					_attributeHierarchy.value = <hierarchy/>;
				
				// add each missing category
				parent = <category name="Data Tables"/>;
				_attributeHierarchy.value.appendChild(parent);
				for (i = 0; i < tables.length; i++)
				{
					metadata = tables[i];
					tag = <category/>;
					for (attrName in metadata)
						tag['@'+attrName] = metadata[attrName];
					parent.appendChild(tag);
				}
				
				parent = <category name="Geometry Collections"/>;
				_attributeHierarchy.value.appendChild(parent);
				for (i = 0; i < geoms.length; i++)
				{
					metadata = geoms[i];
					tag = <attribute/>;
					for (attrName in metadata)
						tag['@'+attrName] = metadata[attrName];
					parent.appendChild(tag);
				}
				
				_attributeHierarchy.detectChanges();
//			}
//			catch (e:Error)
//			{
//				reportError(e, "Unable to generate hierarchy");
//			}
		}
		
		/**
		 * Creates a lookup from item to index.
		 */
		private function createLookup(items:Array):Object
		{
			var lookup:Dictionary = new Dictionary(true);
			items.forEach(function(id:*, index:*, array:*):void { lookup[id] = index; });
			return lookup;
		}

		private function handleColumnEntities(event:ResultEvent, hierarcyNode_entityIds:Array):void
		{
			if (objectWasDisposed(this))
				return;

			var hierarchyNode:XML = hierarcyNode_entityIds[0] as XML; // the node to add the list of columns to
			var entityIds:Array = hierarcyNode_entityIds[1] as Array; // ordered list of ids
			var orderLookup:Object = createLookup(entityIds);

			hierarchyNode = _attributeHierarchy.getNodeFromPath(_attributeHierarchy.getPathFromNode(hierarchyNode));
			if (!hierarchyNode)
				return;
			
			try
			{
				var entities:Array = event.result as Array;
				AsyncSort.sortImmediately(
					entities,
					function(entity1:Object, entity2:Object):int
					{
						return ObjectUtil.numericCompare(orderLookup[entity1.id], orderLookup[entity2.id]);
					}
				);
				
				// append list of attributes
				for (var i:int = 0; i < entities.length; i++)
				{
					var metadata:Object = entities[i].publicMetadata;
					metadata[ENTITY_ID] = entities[i].id;
					var node:XML = <attribute/>;
					for (var property:String in metadata)
						if (metadata[property])
							node['@'+property] = metadata[property];
					hierarchyNode.appendChild(node);
				}
			}
			catch (e:Error)
			{
				reportError(e, "Unable to process result from servlet: "+ObjectUtil.toString(event.result));
			}
			finally
			{
				//trace("updated hierarchy: "+ attributeHierarchy);
				_attributeHierarchy.detectChanges();
			}
		}
		private function handleFault(event:FaultEvent, token:Object = null):void
		{
			if (objectWasDisposed(dataService))
				return;
			reportError(event);
			trace('async token',ObjectUtil.toString(token));
		}
		
		/**
		 * This function must be implemented by classes by extend AbstractDataSource.
		 * This function should make a request to the source to fill in the proxy column.
		 * @param columnReference An object that contains all the information required to request the column from this IDataSource. 
		 * @param A ProxyColumn object that will be updated when the column data is ready.
		 */
		override protected function requestColumnFromSource(columnReference:IColumnReference, proxyColumn:ProxyColumn):void
		{
			var hierarchyRef:HierarchyColumnReference = columnReference as HierarchyColumnReference;
			if (!hierarchyRef)
				return handleUnsupportedColumnReference(columnReference, proxyColumn);

			var pathInHierarchy:XML = hierarchyRef.hierarchyPath.value || <empty/>;
			
			//trace("requestColumnFromSource()",pathInHierarchy.toXMLString());
			var leafNode:XML = HierarchyUtils.getLeafNodeFromPath(pathInHierarchy) || <empty/>;
			proxyColumn.setMetadata(leafNode.copy());
			
			// get metadata properties from XML attributes
			const SQLPARAMS:String = 'sqlParams';
			var params:Object = getAttrs(leafNode, [ENTITY_ID, ColumnMetadata.MIN, ColumnMetadata.MAX, SQLPARAMS], false);
			var columnRequestToken:ColumnRequestToken = new ColumnRequestToken(pathInHierarchy, proxyColumn);
			var query:AsyncToken;
			var _idFields:Array = idFields.getSessionState() as Array;
			
			if (_idFields || params[ENTITY_ID])
			{
				var id:Object = _idFields ? getAttrs(leafNode, _idFields, true) : StandardLib.asNumber(params[ENTITY_ID]);
				var sqlParams:Array = WeaveAPI.CSVParser.parseCSVRow(params[SQLPARAMS]);
				query = dataService.getColumn(id, params[ColumnMetadata.MIN], params[ColumnMetadata.MAX], sqlParams);
			}
			else // backwards compatibility - search using metadata
			{
				getAttrs(leafNode, [ColumnMetadata.DATA_TYPE, 'dataTable', 'name', 'year'], false, params);
				// dataType is only used for backwards compatibility with geometry collections
				if (params[ColumnMetadata.DATA_TYPE] != DataTypes.GEOMETRY)
					delete params[ColumnMetadata.DATA_TYPE];
				
				query = dataService.getColumnFromMetadata(params);
			}
			addAsyncResponder(query, handleGetAttributeColumn, handleGetAttributeColumnFault, columnRequestToken);
			WeaveAPI.ProgressIndicator.addTask(query, proxyColumn);
		}
		
		/**
		 * @param node An XML node
		 * @param attrNames A list of attribute names
		 * @param forUniqueId Set this to true when these attributes are the ones specified by idFields to uniquely identify a column.
		 * @param output An object to store the values.
		 * @return An object containing the attribute values.  Empty strings will be omitted, unless all values were empty and forUniqueId == true.
		 */
		private function getAttrs(node:XML, attrNames:Array, forUniqueId:Boolean, output:Object = null):Object
		{
			var attrName:String;
			var found:Boolean = false;
			var result:Object = output || {};
			for each (attrName in attrNames)
			{
				// ignore missing values
				var attr:String = node.attribute(attrName);
				if (attr)
				{
					found = true;
					result[attrName] = attr;
				}
			}
			if (!found && forUniqueId)
				for each (attrName in attrNames)
					result[attrName] = '';
			return result;
		}
		
		private function handleGetAttributeColumnFault(event:FaultEvent, request:ColumnRequestToken):void
		{
			if (request.proxyColumn.wasDisposed)
				return;
			
			var xml:XML = HierarchyUtils.getLeafNodeFromPath(request.pathInHierarchy) || request.pathInHierarchy;
			var msg:String = "Error retrieving column: " + xml.toXMLString() + ' (' + event.fault.faultString + ')';
			reportError(event.fault, msg, request);
			
			request.proxyColumn.setInternalColumn(ProxyColumn.undefinedColumn);
		}
//		private function handleGetAttributeColumn(event:ResultEvent, token:Object = null):void
//		{
//			DebugUtils.callLater(5000, handleGetAttributeColumn2, arguments);
//		}
		private function handleGetAttributeColumn(event:ResultEvent, request:ColumnRequestToken):void
		{
			if (request.proxyColumn.wasDisposed)
				return;
			
			var pathInHierarchy:XML = request.pathInHierarchy;
			var proxyColumn:ProxyColumn = request.proxyColumn;
			var hierarchyNode:XML = HierarchyUtils.getLeafNodeFromPath(pathInHierarchy);
			// if the node does not exist in hierarchy anymore, create a new XML separate from the hierarchy.
			if (!hierarchyNode)
				hierarchyNode = <attribute/>;
			else
				proxyColumn.setMetadata(hierarchyNode);

			try
			{
				if (!event.result)
				{
					var msg:String = "Did not receive any data from service for attribute column: "
						+ HierarchyUtils.getLeafNodeFromPath(request.pathInHierarchy).toXMLString();
					reportError(msg);
					return;
				}
				
				var result:AttributeColumnData = AttributeColumnData(event.result);
				//trace("handleGetAttributeColumn",pathInHierarchy.toXMLString());
	
				// fill in metadata
				for (var metadataName:String in result.metadata)
				{
					var metadataValue:String = result.metadata[metadataName];
					if (metadataValue)
						hierarchyNode['@' + metadataName] = metadataValue;
				}
				hierarchyNode['@'+ENTITY_ID] = result.id;
				
				// special case for geometry column
				var dataType:String = ColumnUtils.getDataType(proxyColumn);
				var isGeom:Boolean = ObjectUtil.stringCompare(dataType, DataTypes.GEOMETRY, true) == 0;
				if (isGeom && result.data == null)
				{
					var tileService:IWeaveGeometryTileService = dataService.createTileService(result.id);
					proxyColumn.setInternalColumn(new StreamedGeometryColumn(result.metadataTileDescriptors, result.geometryTileDescriptors, tileService, hierarchyNode));
					return;
				}
	
				// stop if no data
				if (result.data == null)
				{
					proxyColumn.setInternalColumn(ProxyColumn.undefinedColumn);
					return;
				}
				
				var keyType:String = ColumnUtils.getKeyType(proxyColumn);
				var keysVector:Vector.<IQualifiedKey> = new Vector.<IQualifiedKey>();
				var setRecords:Function = function():void
				{
					if (isGeom) // result.data is an array of PGGeom objects.
					{
						var geometriesVector:Vector.<GeneralizedGeometry> = new Vector.<GeneralizedGeometry>();
						var createGeomColumn:Function = function():void
						{
							var newGeometricColumn:GeometryColumn = new GeometryColumn(hierarchyNode);
							newGeometricColumn.setGeometries(keysVector, geometriesVector);
							proxyColumn.setInternalColumn(newGeometricColumn);
						};
						var pgGeomTask:Function = PGGeomUtil.newParseTask(result.data, geometriesVector);
						WeaveAPI.StageUtils.startTask(proxyColumn, pgGeomTask, WeaveAPI.TASK_PRIORITY_3_PARSING, createGeomColumn);
					}
					else if (result.thirdColumn != null)
					{
						// hack for dimension slider
						var newColumn:SecondaryKeyNumColumn = new SecondaryKeyNumColumn(hierarchyNode);
						newColumn.baseTitle = String(hierarchyNode.@baseTitle);
						var secKeyVector:Vector.<String> = Vector.<String>(result.thirdColumn);
						newColumn.updateRecords(keysVector, secKeyVector, result.data);
						proxyColumn.setInternalColumn(newColumn);
						proxyColumn.setMetadata(null); // this will allow SecondaryKeyNumColumn to use its getMetadata() code
					}
					else if (ObjectUtil.stringCompare(dataType, DataTypes.NUMBER, true) == 0)
					{
						var newNumericColumn:NumberColumn = new NumberColumn(hierarchyNode);
						newNumericColumn.setRecords(keysVector, Vector.<Number>(result.data));
						proxyColumn.setInternalColumn(newNumericColumn);
					}
					else if (ObjectUtil.stringCompare(dataType, DataTypes.DATE, true) == 0)
					{
						var newDateColumn:DateColumn = new DateColumn(hierarchyNode);
						newDateColumn.setRecords(keysVector, Vector.<String>(result.data));
						proxyColumn.setInternalColumn(newDateColumn);
					}
					else
					{
						var newStringColumn:StringColumn = new StringColumn(hierarchyNode);
						newStringColumn.setRecords(keysVector, Vector.<String>(result.data));
						proxyColumn.setInternalColumn(newStringColumn);
					} 
					//trace("column downloaded: ",proxyColumn);
					// run hierarchy callbacks because we just modified the hierarchy.
					_attributeHierarchy.detectChanges();
				};
				
				(WeaveAPI.QKeyManager as QKeyManager).getQKeysAsync(keyType, result.keys, proxyColumn, setRecords, keysVector);
			}
			catch (e:Error)
			{
				trace(this,"handleGetAttributeColumn",pathInHierarchy.toXMLString(),e.getStackTrace());
			}
		}
	}
}

import flash.utils.getTimer;

import weave.data.AttributeColumns.ProxyColumn;
import weave.primitives.GeneralizedGeometry;
import weave.primitives.GeometryType;
import weave.utils.BLGTreeUtils;

/**
 * This object is used as a token in an AsyncResponder.
 */
internal class ColumnRequestToken
{
	public function ColumnRequestToken(pathInHierarchy:XML, proxyColumn:ProxyColumn)
	{
		this.pathInHierarchy = pathInHierarchy;
		this.proxyColumn = proxyColumn;
	}
	public var pathInHierarchy:XML;
	public var proxyColumn:ProxyColumn;
}

/**
 * Static functions for retrieving values from PGGeom objects coming from servlet.
 */
internal class PGGeomUtil
{
	/**
	 * This will generate an asynchronous task function for use with IStageUtils.startTask().
	 * @param pgGeoms An Array of PGGeom beans from a Weave data service.
	 * @param output A vector to store GeneralizedGeometry objects created from the pgGeoms input.
	 * @return A new Function.
	 * @see weave.api.core.IStageUtils
	 */
	public static function newParseTask(pgGeoms:Array, output:Vector.<GeneralizedGeometry>):Function
	{
		var i:int = 0;
		var n:int = pgGeoms.length;
		output.length = n;
		return function(returnTime:int):Number
		{
			for (; i < n; i++)
			{
				if (getTimer() > returnTime)
					return i / n;
				
				var item:Object = pgGeoms[i];
				var geomType:String = GeometryType.fromPostGISType(item[TYPE]);
				var geometry:GeneralizedGeometry = new GeneralizedGeometry(geomType);
				geometry.setCoordinates(item[XYCOORDS], BLGTreeUtils.METHOD_SAMPLE);
				output[i] = geometry;
			}
			return 1;
		};
	}
	
	/**
	 * The name of the type property in a PGGeom bean
	 */
	private static const TYPE:String = 'type';
	
	/**
	 * The name of the xyCoords property in a PGGeom bean
	 */
	private static const XYCOORDS:String = 'xyCoords';
}
