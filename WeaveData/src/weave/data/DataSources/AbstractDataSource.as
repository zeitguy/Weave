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
	import flash.utils.Dictionary;
	import flash.utils.getQualifiedClassName;
	
	import weave.api.WeaveAPI;
	import weave.api.copySessionState;
	import weave.api.core.ICallbackCollection;
	import weave.api.core.IDisposableObject;
	import weave.api.core.ILinkableDynamicObject;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IColumnReference;
	import weave.api.data.IWeaveTreeNode;
	import weave.api.detectLinkableObjectChange;
	import weave.api.getCallbackCollection;
	import weave.api.newDisposableChild;
	import weave.api.newLinkableChild;
	import weave.api.reportError;
	import weave.core.ClassUtils;
	import weave.core.LinkableXML;
	import weave.data.AttributeColumns.ProxyColumn;
	import weave.data.ColumnReferences.HierarchyColumnReference;
	import weave.data.hierarchy.XMLEntityNode;
	import weave.utils.HierarchyUtils;
	
	/**
	 * This is a base class to make it easier to develope a new class that implements IDataSource_old.
	 * To extend this class, the minimum functions to override are:
	 *         initialize(), requestHierarchyFromSource() and requestColumnFromSource().
	 * Optionally, initializationComplete() can also be overridden to control how long column requests are delayed.
	 * 
	 * @author adufilie
	 */
	public class AbstractDataSource implements IDataSource_old, IDisposableObject
	{
		public function AbstractDataSource()
		{
			var cc:ICallbackCollection = getCallbackCollection(this);
			cc.addImmediateCallback(this, uninitialize);
			cc.addGroupedCallback(this, initialize, true);
		}

		/**
		 * Set this to true to enable the debug() function.
		 */
		protected var enableDebug:Boolean = false;

		/**
		 * This function calls trace() using the given arguments if enableDebug is true.
		 * @param traceArgs The arguments to pass to trace().
		 */
		protected function debug(...traceArgs):void
		{
			if (enableDebug)
			{
				traceArgs.unshift(this);
				debugTrace.apply(null, traceArgs);
			}
		}
		
		/**
		 * For each tag matching tagName, replace attribute names of that tag using the nameMapping.
		 * Example usage: convertOldHierarchyFormat(root, 'attribute', {dataTableName: "dataTable", dataType: myFunction})
		 * @param root The root XML hierachy tag.
		 * @param tagName The name of tags that need to be converted from an old format.
		 * @param nameMapping Maps attribute names to new attribute names or functions that convert the old values, with the following signature:  function(value:String):String
		 */
		protected function convertOldHierarchyFormat(root:XML, tagName:String, nameMapping:Object):void
		{
			if (root == null)
				return;
			
			var node:XML;
			var oldName:String;
			var value:String;
			var nodes:XMLList;
			var nameMap:Object;
			var newName:String;
			var valueConverter:Function;

			nodes = root.descendants(tagName);
			for each (node in nodes)
			{
				for (oldName in nameMapping)
				{
					newName = nameMapping[oldName] as String;
					valueConverter = nameMapping[oldName] as Function;
					
					value = node.attribute(oldName);
					if (value) // if there's an old value
					{
						if (valueConverter != null) // if there's a converter
						{
							node['@' + oldName] = valueConverter(value); // convert the old value
						}
						else if (!String(node.attribute(newName))) // if there's no value under the newName
						{
							// rename the attribute from oldName to newName
							delete node['@' + oldName];
							node['@' + newName] = value;
						}
					}
				}
			}
		}
		
		/**
		 * This variable is set to false when the session state changes and true when initialize() is called.
		 */
		private var _initializeCalled:Boolean = false;
		
		/**
		 * Classes that extend AbstractDataSource can define their own replacement for this function.
		 * All column requests will be delayed as long as this accessor function returns false.
		 * The default behavior is to return false during the time between a change in the session state and when initialize() is called.
		 */		
		protected function get initializationComplete():Boolean
		{
			return _initializeCalled;
		}

		/**
		 * This function sets initialized to false.
		 */
		private function uninitialize():void
		{
			debug("uninitialize");
			_initializeCalled = false;
		}
		
		/**
		 * This function must be implemented by classes that extend AbstractDataSource.
		 * It will be called the frame after the session state for the data source changes.
		 * When overriding this function, super.initialize() should be called.
		 */
		protected function initialize():void
		{
			// just in case the XML was modified, detect those changes now.
			_attributeHierarchy.detectChanges();

			// set initialized to true so other parts of the code know if this function has been called.
			_initializeCalled = true;

			debug("initialize");

			// TODO: check each column previously provided by getAttributeColumn()

			// initialize hierarchy if it is null
			if (_attributeHierarchy.value == null && detectLinkableObjectChange(_requestedHierarchySubtreeStringMap, _attributeHierarchy))
			{
				// Clear the list of requested hierarchy subtrees.
				// This will allow the hierarchy to be filled in automatically
				// if its contents were cleared with that intention.
				_requestedHierarchySubtreeStringMap = {};
				detectLinkableObjectChange(_requestedHierarchySubtreeStringMap, _attributeHierarchy);
				initializeHierarchySubtree(null);
			}
			
			handleAllPendingColumnRequests();

			debug("initialize completed");
		}
		
		/**
		 * This function must be implemented by classes by extend AbstractDataSource.
		 * This function should make a request to the source to fill in the hierarchy at the given subtree.
		 * This function will only be called once per subtreeNode.
		 * @param subtreeNode A pointer to a node in the hierarchy representing the root of the subtree to request from the source.
		 */
		/* abstract */ protected function requestHierarchyFromSource(subtreeNode:XML = null):void { }

		/**
		 * This function must be implemented by classes that extend AbstractDataSource.
		 * This function should make a request to the source to fill in the proxy column.
		 * @param columnReference An object that contains all the information required to request the column from this IDataSource. 
		 * @param A ProxyColumn object that will be updated when the column data is ready.
		 */
		/* abstract */ protected function requestColumnFromSource(columnReference:IColumnReference, proxyColumn:ProxyColumn):void { }

		public function refreshHierarchy():void
		{
			_attributeHierarchy.setSessionState(null);
		}

		protected var _rootNode:IWeaveTreeNode;
		
		/**
		 * Gets the root node of the attribute hierarchy.
		 */
		public function getHierarchyRoot():IWeaveTreeNode
		{
			if (!(_rootNode is XMLEntityNode))
				_rootNode = new XMLEntityNode();
			(_rootNode as XMLEntityNode).dataSourceName = WeaveAPI.globalHashMap.getName(this);
			(_rootNode as XMLEntityNode).xml = _attributeHierarchy.value;
			return _rootNode;
		}
		
		/**
		 * Populates a LinkableDynamicObject with an IColumnReference corresponding to a node in the attribute hierarchy.
		 */
		public function getColumnReference(node:IWeaveTreeNode, output:ILinkableDynamicObject):Boolean
		{
			if (node.getSource() != this || node.isBranch())
				return false;
			
			var xmlnode:XMLEntityNode = node as XMLEntityNode;
			if (xmlnode)
			{
				getCallbackCollection(output).delayCallbacks();
				var hcr:HierarchyColumnReference = output.requestLocalObject(HierarchyColumnReference, false);
				hcr.dataSourceName.value = xmlnode.dataSourceName;
				hcr.hierarchyPath.value = HierarchyUtils.getPathFromNode(_attributeHierarchy.value, xmlnode.xml);
				getCallbackCollection(output).resumeCallbacks();
				return true;
			}
			return false
		}

		/**
		 * @return An AttributeHierarchy object that will be updated when new pieces of the hierarchy are filled in.
		 */
		public function get attributeHierarchy():LinkableXML
		{
			return _attributeHierarchy;
		}

		// this is returned by a public getter
		protected const _attributeHierarchy:LinkableXML = newLinkableChild(this, LinkableXML, handleHierarchyChange);

		/**
		 * This is a list of DelayedColumnRequest objects.
		 */
		private var _pendingColumnRequests:Array = [];
		
		/**
		 * This maps a requested hierarchy subtree xml string to a value of true.
		 * If a subtree node has not been requested yet, it will not appear in this Object.
		 */
		protected var _requestedHierarchySubtreeStringMap:Object = new Object();
		
		/**
		 * If the hierarchy subtree pointed to subtreeNode 
		 * @param subtreeNode A pointer to a node in the hierarchy representing the root of the subtree to request from the source.
		 */
		public function initializeHierarchySubtree(subtreeNode:XML = null):void
		{
			var pathString:String = '';
			if (subtreeNode == null)
			{
				// do nothing if root node already has children
				if (_attributeHierarchy.value != null && _attributeHierarchy.value.children().length() > 0)
					return;
			}
			else
			{
				var path:XML = HierarchyUtils.getPathFromNode(_attributeHierarchy.value, subtreeNode);
				// do nothing if path does not exist or node already has children
				if (path == null || subtreeNode.children().length() > 0)
					return;
				pathString = path.toXMLString();
			}
			debug("initializeHierarchySubtree", pathString);
			if (_requestedHierarchySubtreeStringMap[pathString] == undefined)
			{
				_requestedHierarchySubtreeStringMap[pathString] = true;
				WeaveAPI.StageUtils.callLater(this, requestHierarchyFromSource, [subtreeNode], WeaveAPI.TASK_PRIORITY_0_IMMEDIATE);
			}
			else
			{
				debug("already initialized", pathString);
			}
		}

		/**
		 * This function gets called when the hierarchy callbacks are run.
		 * This function can be defined with override by classes that extend AbstractDataSource.
		 */
		protected function handleHierarchyChange():void
		{
		}
		
		/**
		 * This function creates a new ProxyColumn object corresponding to the columnReference and queues up the request for the column.
		 * @param columnReference An object that contains all the information required to request the column from this IDataSource. 
		 * @return A ProxyColumn object that will be updated when the column data is ready.
		 */
		public function getAttributeColumn(columnReference:IColumnReference):IAttributeColumn
		{
			if (columnReference.getDataSource() != this)
				return ProxyColumn.undefinedColumn;
			
			// we need to make a copy of the column reference because we don't want
			// the session state to change before we actually request the column.
			var refClass:Class = ClassUtils.getClassDefinition(getQualifiedClassName(columnReference));
			var refCopy:IColumnReference = newDisposableChild(this, refClass);
			copySessionState(columnReference, refCopy);
			
			var proxyColumn:ProxyColumn = newDisposableChild(this, ProxyColumn);

			// Save pointers to the column and the reference.
			_proxyColumnToReferenceMap[proxyColumn] = refCopy;

			debug('getAttributeColumn', refCopy.getHashCode());
			
			var dcr:DelayedColumnRequest = new DelayedColumnRequest(refCopy, proxyColumn);
			WeaveAPI.ProgressIndicator.addTask(dcr, proxyColumn);
			handlePendingColumnRequest(dcr);
			
			return proxyColumn;
		}

		/**
		 * This function will call requestColumnFromSource() if the hierarchyPointer in the column is now valid.
		 * Otherwise, it will call delayColumnRequest() again.
		 * This function may be overridden by classes that extend AbstractDataSource.
		 * However, if the extending class decides it wants to call requestColumnFromSource()
		 * for the pending column, it is recommended to call super.handlePendingColumnRequest() instead.
		 * @param request The request that needs to be handled.
		 */
		private function handlePendingColumnRequest(request:DelayedColumnRequest):void
		{
			// If data source is already initialized (session state is stable, not currently changing), we can request the column now.
			// Otherwise, we have to wait.
			if (initializationComplete)
			{
				debug('requestColumnFromSource', request.columnReference.getHashCode());
				
				WeaveAPI.StageUtils.callLater(request.proxyColumn, requestColumnFromSource, [request.columnReference, request.proxyColumn]);
				WeaveAPI.StageUtils.callLater(request.proxyColumn, WeaveAPI.ProgressIndicator.removeTask, [request]);
				//requestColumnFromSource(request.columnReference, request.proxyColumn);
			}
			else
			{
				delayColumnRequest(request);
			}
		}

		/**
		 * This will put an initialized proxy column into the list of pending requests.
		 * It will also call initializeHierarchySubtree() for a subtree of the hierarchy, if a subtree is missing.
		 * This function can be overridden to have different behavior, but this definition is recommended.
		 * @param request The request that needs to be handled.
		 */
		private function delayColumnRequest(request:DelayedColumnRequest):void
		{
			debug('delayColumnRequest', request.columnReference.getHashCode());
			
			_pendingColumnRequests.push(request);
		}
		
		/**
		 * This function will call handlePendingColumnRequest() on each pending column request.
		 */
		private function handleAllPendingColumnRequests():void
		{
			// swap out pending requests with a new array so we don't go in an infinite loop.
			var oldRequests:Array = _pendingColumnRequests;
			_pendingColumnRequests = [];
			for each (var oldRequest:DelayedColumnRequest in oldRequests)
				handlePendingColumnRequest(oldRequest);
		}
		
		/**
		 * Use this function to report an error for an unsupported column reference.
		 * @param columnReference An object that contains all the information required to request the column from this IDataSource. 
		 * @return A ProxyColumn object that will be updated when the column data is ready.
		 */
		protected function handleUnsupportedColumnReference(columnReference:IColumnReference, proxyColumn:ProxyColumn):void
		{
			reportError(this + " Unsupported column reference type: " + getQualifiedClassName(columnReference));
			proxyColumn.setInternalColumn(ProxyColumn.undefinedColumn);
			return;
		}
		
		/**
		 * The keys in this Dictionary are ProxyColumn objects created by this data source.
		 * The values in this Dictionary are the corresponding IColumnReference objects.
		 * This dictionary uses strong keys to prevent garbage-collection.
		 */		
		private const _proxyColumnToReferenceMap:Dictionary = new Dictionary(false);
		
		/**
		 * This function should be called when the IDataSource is no longer in use.
		 * All existing pointers to objects should be set to null so they can be garbage collected.
		 */
		public function dispose():void
		{
			debug('dispose');
			
			_initializeCalled = false;
			_pendingColumnRequests.length = 0;
			var key:*
			for (key in _proxyColumnToReferenceMap)
			{
				var proxyColumn:ProxyColumn = key as ProxyColumn;
				// clear the data and allow callbacks to run.
				proxyColumn.setInternalColumn(ProxyColumn.undefinedColumn);
				while (proxyColumn.callbacksAreDelayed)
					proxyColumn.resumeCallbacks();
			}
			// clean up pointers to columns
			for (key in _proxyColumnToReferenceMap)
				delete _proxyColumnToReferenceMap[key];
		}
	}
}

import weave.api.data.IColumnReference;
import weave.data.AttributeColumns.ProxyColumn;

/**
 * @private
 * This is used internally as an Array item in the list of pending column requests.
 * A DelayedColumnRequest object has a pointer to a ProxyColumn object that still needs to be filled in with data,
 * along with the corresponding IColumnReference that was given to getAttributeColumn().
 */
internal class DelayedColumnRequest
{
	public function DelayedColumnRequest(columnReference:IColumnReference, proxyColumn:ProxyColumn)
	{
		this.columnReference = columnReference;
		this.proxyColumn = proxyColumn;
	}
	public var columnReference:IColumnReference;
	public var proxyColumn:ProxyColumn;
}
