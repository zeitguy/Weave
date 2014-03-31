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
	import weave.api.WeaveAPI;
	import weave.api.core.ILinkableDynamicObject;
	import weave.api.core.ILinkableHashMap;
	import weave.api.core.ILinkableObject;
	import weave.api.data.ColumnMetadata;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IAttributeHierarchy;
	import weave.api.data.IColumnReference;
	import weave.api.data.IDataSource;
	import weave.api.data.IEntityTreeNode;
	import weave.api.getCallbackCollection;
	import weave.api.newLinkableChild;
	import weave.api.registerLinkableChild;
	import weave.data.AttributeColumns.CSVColumn;
	import weave.data.AttributeColumns.EquationColumn;
	import weave.data.AttributeColumns.ProxyColumn;
	import weave.data.ColumnReferences.HierarchyColumnReference;
	import weave.data.hierarchy.DataSourceTreeNode;
	import weave.primitives.AttributeHierarchy;
	import weave.utils.HierarchyUtils;

	/**
	 * This is a class to keep an updated list of all the available data sources
	 * 
	 * @author skolman
	*/
	public class MultiDataSource implements IDataSource
	{
		public function MultiDataSource()
		{
			var dependencies:Array = _root.getObjects(IDataSource).concat(_root.getObjects(EquationColumn), _root.getObjects(CSVColumn));
			for each (var obj:ILinkableObject in dependencies)
				addDependency(obj);
			
			_root.childListCallbacks.addImmediateCallback(this, handleWeaveChildListChange);
			handleHierarchyChange();
		}
		
		private static var _instance:MultiDataSource;
		public static function get instance():MultiDataSource
		{
			if (!_instance)
				_instance = new MultiDataSource();
			return _instance;
		}
		private var _root:ILinkableHashMap = WeaveAPI.globalHashMap;
		
		public function refreshHierarchy():void
		{
			var sources:Array = WeaveAPI.globalHashMap.getObjects(IDataSource);
			for each (var source:IDataSource in sources)
				source.refreshHierarchy();
		}
		
		protected const _rootNode:IEntityTreeNode = new DataSourceTreeNode();
		
		/**
		 * Gets the root node of the attribute hierarchy.
		 */
		public function getHierarchyRoot():IEntityTreeNode
		{
			return _rootNode;
		}
		
		/**
		 * Populates a LinkableDynamicObject with an IColumnReference corresponding to a node in the attribute hierarchy.
		 */
		public function getColumnReference(node:IEntityTreeNode, output:ILinkableDynamicObject):void
		{
			var ds:IDataSource = node.getSource() as IDataSource;
			if (!ds)
			{
				output.removeObject();
				return;
			}
			
			ds.getColumnReference(node, output);
		}
		
		/**
		 * @return An AttributeHierarchy object that will be updated when new pieces of the hierarchy are filled in.
		 */
		private const _attributeHierarchy:AttributeHierarchy = newLinkableChild(this, AttributeHierarchy);
		public function get attributeHierarchy():IAttributeHierarchy
		{
			return _attributeHierarchy;
		}
		
		private function addDependency(obj:ILinkableObject):void
		{
			if (!(obj is MultiDataSource) && (obj is IDataSource || obj is IAttributeColumn))
			{
				if (obj is IDataSource)
					obj = (obj as IDataSource).attributeHierarchy;
				
				registerLinkableChild(this, obj);
				getCallbackCollection(obj).addGroupedCallback(this, handleHierarchyChange);
			}
		}
		private function handleWeaveChildListChange():void
		{
			// add callback to new IDataSource or IAttributeColumn so we refresh the hierarchy when it changes
			addDependency(_root.childListCallbacks.lastObjectAdded);
			handleHierarchyChange();
		}
		
		private function handleHierarchyChange():void
		{
			var rootNode:XML = <hierarchy name="DataSources"/>;
			
			// add category for each IDataSource
			var sources:Array = _root.getObjects(IDataSource);
			for each(var source:IDataSource in sources)
			{
				if(!(source is MultiDataSource))
				{
					var xml:XML = (source.attributeHierarchy as AttributeHierarchy).value;
					if (xml != null)
					{
						var category:XML = xml.copy();
						category.setName("category");
						category.@dataSourceName = _root.getName(source);
						rootNode.appendChild(category);
					}
				}
			}
			
			// add category for global column objects
			// TEMPORARY SOLUTION -- only allow EquationColumn and CSVColumn
			var eqCols:Array = _root.getObjects(EquationColumn).concat(_root.getObjects(CSVColumn));
			if (eqCols.length > 0)
			{
				var globalCategory:XML = <category title="Equations"/>;
				for each(var col:IAttributeColumn in eqCols)
				{
					globalCategory.appendChild(<attribute name={ _root.getName(col) } title={ col.getMetadata(ColumnMetadata.TITLE) }/>);
				}
				rootNode.appendChild(globalCategory);
			}
			
			_attributeHierarchy.value = rootNode;
			
		}
		
		
		/**
		 * @param subtreeNode A node in the hierarchy representing the root of the subtree to initialize, or null to initialize the root of the hierarchy.
		 */
		public function initializeHierarchySubtree(subtreeNode:XML = null):void
		{
			
			var path:XML = _attributeHierarchy.getPathFromNode(subtreeNode);
			if (path == null)
				return;
			
			if (path.category.length() == 0)
				return;
			path = path.category[0];
			
			path.setName("hierarchy");
			
			var sourceName:String = path.@dataSourceName;
			
			var source:IDataSource = _root.getObject(sourceName) as IDataSource;
			
			if (source == null)
				return;
				
			
			delete path.@dataSourceName;
			
			var xml:XML = (source.attributeHierarchy as AttributeHierarchy).value;
			var currentSubTreeNode:XML = HierarchyUtils.getNodeFromPath(xml, path);
			
			source.initializeHierarchySubtree(currentSubTreeNode);
		}
		
		public function getAttributeColumn(columnReference:IColumnReference):IAttributeColumn
		{
			if (columnReference.getDataSource() == null)
			{
				// special case -- global column hack
				var hcr:HierarchyColumnReference = columnReference as HierarchyColumnReference;
				try
				{
					var name:String = HierarchyUtils.getLeafNodeFromPath(hcr.hierarchyPath.value).@name;
					return _root.getObject(name) as IAttributeColumn;
				}
				catch (e:Error)
				{
					// do nothing
				}
				return ProxyColumn.undefinedColumn;
			}
			
			return WeaveAPI.AttributeColumnCache.getColumn(columnReference);
		}
	}
}