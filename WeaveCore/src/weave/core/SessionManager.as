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

package weave.core
{
	import avmplus.DescribeType;
	
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.events.Event;
	import flash.events.EventPhase;
	import flash.system.Capabilities;
	import flash.utils.Dictionary;
	import flash.utils.getQualifiedClassName;
	import flash.utils.getTimer;
	
	import mx.binding.utils.BindingUtils;
	import mx.binding.utils.ChangeWatcher;
	import mx.core.UIComponent;
	import mx.core.mx_internal;
	import mx.rpc.AsyncResponder;
	import mx.rpc.AsyncToken;
	import mx.utils.ObjectUtil;
	
	import weave.api.WeaveAPI;
	import weave.api.core.ICallbackCollection;
	import weave.api.core.IDisposableObject;
	import weave.api.core.ILinkableCompositeObject;
	import weave.api.core.ILinkableDynamicObject;
	import weave.api.core.ILinkableHashMap;
	import weave.api.core.ILinkableObject;
	import weave.api.core.ILinkableObjectWithBusyStatus;
	import weave.api.core.ILinkableVariable;
	import weave.api.core.ISessionManager;
	import weave.api.reportError;
	import weave.compiler.StandardLib;
	import weave.utils.AsyncSort;
	import weave.utils.Dictionary2D;

	/**
	 * This is a collection of core functions in the Weave session framework.
	 * 
	 * @author adufilie
	 */
	public class SessionManager implements ISessionManager
	{
		public var debugBusyTasks:Boolean = false;
		
		/**
		 * @inheritDoc
		 */
		public function newLinkableChild(linkableParent:Object, linkableChildType:Class, callback:Function = null, useGroupedCallback:Boolean = false):*
		{
			if (!(linkableParent is ILinkableObject))
				throw new Error("newLinkableChild(): Parent does not implement ILinkableObject.");
			
			var childQName:String = getQualifiedClassName(linkableChildType);
			if (!ClassUtils.classImplements(childQName, ILinkableObjectQualifiedClassName))
				throw new Error("newLinkableChild(): Child class does not implement ILinkableObject.");
			
			var linkableChild:ILinkableObject = new linkableChildType() as ILinkableObject;
			return registerLinkableChild(linkableParent, linkableChild, callback, useGroupedCallback);
		}
		
		/**
		 * @inheritDoc
		 */
		public function registerLinkableChild(linkableParent:Object, linkableChild:ILinkableObject, callback:Function = null, useGroupedCallback:Boolean = false):*
		{
			if (!(linkableParent is ILinkableObject))
				throw new Error("registerLinkableChild(): Parent does not implement ILinkableObject.");
			if (!(linkableChild is ILinkableObject))
				throw new Error("registerLinkableChild(): Child parameter cannot be null.");
			if (linkableParent == linkableChild)
				throw new Error("registerLinkableChild(): Invalid attempt to register sessioned property having itself as its parent");
			
			// add a callback that will be cleaned up when the parent is disposed of.
			// this callback will be called BEFORE the child triggers the parent callbacks.
			if (callback != null)
			{
				var cc:ICallbackCollection = getCallbackCollection(linkableChild);
				if (useGroupedCallback)
					cc.addGroupedCallback(linkableParent as ILinkableObject, callback);
				else
					cc.addImmediateCallback(linkableParent as ILinkableObject, callback);
			}
			
			// if the child doesn't have an owner yet, this parent is the owner of the child
			// and the child should be disposed when the parent is disposed.
			// registerDisposableChild() also initializes the required Dictionaries.
			registerDisposableChild(linkableParent, linkableChild);

			// only continue if the child is not already registered with the parent
			if (childToParentDictionaryMap[linkableChild][linkableParent] === undefined)
			{
				// remember this child-parent relationship
				childToParentDictionaryMap[linkableChild][linkableParent] = true;
				parentToChildDictionaryMap[linkableParent][linkableChild] = true;
				
				// make child changes trigger parent callbacks
				var parentCC:ICallbackCollection = getCallbackCollection(linkableParent as ILinkableObject);
				// set alwaysCallLast=true for triggering parent callbacks, so parent will be triggered after all the other child callbacks
				getCallbackCollection(linkableChild).addImmediateCallback(linkableParent, parentCC.triggerCallbacks, false, true); // parent-child relationship
			}

			return linkableChild;
		}
		
		/**
		 * @inheritDoc
		 */
		public function newDisposableChild(disposableParent:Object, disposableChildType:Class):*
		{
			return registerDisposableChild(disposableParent, new disposableChildType());
		}
		
		/**
		 * @inheritDoc
		 */
		public function registerDisposableChild(disposableParent:Object, disposableChild:Object):*
		{
			// if this parent has no owner-to-child mapping, initialize it now with parent-to-child mapping
			if (ownerToChildDictionaryMap[disposableParent] === undefined)
			{
				ownerToChildDictionaryMap[disposableParent] = new Dictionary(true); // weak links to be GC-friendly
				parentToChildDictionaryMap[disposableParent] = new Dictionary(true); // weak links to be GC-friendly
			}
			// if this child has no owner yet...
			if (childToOwnerMap[disposableChild] === undefined)
			{
				// make this first parent the owner
				childToOwnerMap[disposableChild] = disposableParent;
				ownerToChildDictionaryMap[disposableParent][disposableChild] = true;
				// initialize the parent dictionary for this child
				childToParentDictionaryMap[disposableChild] = new Dictionary(true); // weak links to be GC-friendly
			}
			return disposableChild;
		}
		
		/**
		 * Use this function with care.  This will remove child objects from the session state of a parent and
		 * stop the child from triggering the parent callbacks.
		 * @param parent A parent that the specified child objects were previously registered with.
		 * @param child The child object to unregister from the parent.
		 */
		public function unregisterLinkableChild(parent:ILinkableObject, child:ILinkableObject):void
		{
			if (childToParentDictionaryMap[child])
				delete childToParentDictionaryMap[child][parent];
			if (parentToChildDictionaryMap[parent])
				delete parentToChildDictionaryMap[parent][child];
			getCallbackCollection(child).removeCallback(getCallbackCollection(parent).triggerCallbacks);
		}
		
		/**
		 * This function will add or remove child objects from the session state of a parent.  Use this function
		 * with care because the child will no longer be "sessioned."  The child objects will continue to trigger the
		 * callbacks of the parent object, but they will no longer be considered a part of the parent's session state.
		 * If you are not careful, this will break certain functionalities that depend on the session state of the parent.
		 * @param parent A parent that the specified child objects were previously registered with.
		 * @param child The child object to remove from the session state of the parent.
		 */
		public function excludeLinkableChildFromSessionState(parent:ILinkableObject, child:ILinkableObject):void
		{
			if (parent == null || child == null)
			{
				reportError("SessionManager.excludeLinkableChildFromSessionState(): Parameters to this function cannot be null.");
				return;
			}
			if (childToParentDictionaryMap[child] !== undefined && childToParentDictionaryMap[child][parent])
				childToParentDictionaryMap[child][parent] = false;
			if (parentToChildDictionaryMap[parent] !== undefined && parentToChildDictionaryMap[parent][child])
				parentToChildDictionaryMap[parent][child] = false;
		}
		
		/**
		 * @private
		 * This function will return all the child objects that have been registered with a parent.
		 * @param parent A parent object to get the registered children of.
		 * @return An Array containing a list of linkable objects that have been registered as children of the specified parent.
		 *         This list includes all children that have been registered, even those that do not appear in the session state.
		 */
		private function _getRegisteredChildren(parent:ILinkableObject):Array
		{
			var result:Array = [];
			if (parentToChildDictionaryMap[parent] !== undefined)
				for (var key:* in parentToChildDictionaryMap[parent])
					result.push(key);
			return result;
		}

		/**
		 * @inheritDoc
		 */
		public function getLinkableOwner(child:ILinkableObject):ILinkableObject
		{
			return childToOwnerMap[child] as ILinkableObject;
		}
		
		public static const TREE_LABEL:String = 'label';
		public static const TREE_OBJECT:String = 'object';
		public static const TREE_CHILDREN:String = 'children';

		/**
		 * @param root The linkable object to be placed at the root node of the tree.
		 * @return A tree of nodes with the properties "label", "object", and "children"
		 */
		public function getSessionStateTree(object:ILinkableObject, objectName:String, objectTypeFilter:*=null):Object
		{
			var result:Object = {};
			result[TREE_LABEL] = objectName;
			result[TREE_OBJECT] = object;
			result[TREE_CHILDREN] = [];
			
			var names:Array = [];
			var childObject:ILinkableObject;
			var tempObject:Object;
			var ignoreList:Dictionary = new Dictionary(true);
			if (object is ILinkableHashMap)
			{
				names = (object as ILinkableHashMap).getNames();
				
				var sessionObjects:Array = (object as ILinkableHashMap).getObjects();
				
				for (var i:int = 0; i < names.length; i++)
				{
					childObject = sessionObjects[i];
					if (childToParentDictionaryMap[childObject] && childToParentDictionaryMap[childObject][object])
					{
						// don't include duplicate siblings
						if (ignoreList[childObject] != undefined)
							continue;
						ignoreList[childObject] = true;
						
						// get subtree
						tempObject = getSessionStateTree(childObject,names[i],objectTypeFilter);
						if (tempObject != null)
							result[TREE_CHILDREN].push(tempObject);
					}
				}
			}
			else
			{
				if (object is ILinkableDynamicObject)
				{
					// do not show static object in tree
					names = (object as ILinkableDynamicObject).globalName ? null : [null];
				}
				else if (object)
				{
					names = getLinkablePropertyNames(object);
				}
				for each (var name:String in names)
				{
					if (object is ILinkableDynamicObject)
						childObject = (object as ILinkableDynamicObject).internalObject;
					else
						childObject = object[name];
					if (!childObject)
						continue;
					if (childToParentDictionaryMap[childObject] && childToParentDictionaryMap[childObject][object])
					{
						// don't include duplicate siblings
						if (ignoreList[childObject] != undefined)
							continue;
						ignoreList[childObject] = true;
						
						// get subtree
						tempObject = getSessionStateTree(childObject, name, objectTypeFilter);
						if (tempObject != null)
							result[TREE_CHILDREN].push(tempObject);
					}
				}
			}
			
			if (result[TREE_CHILDREN].length == 0)
				result[TREE_CHILDREN] = null;
			if (objectTypeFilter == null)
				return result;
			if (result[TREE_CHILDREN] == null && !(object is objectTypeFilter))
				return null;
			return result;
		}

		/**
		 * @inheritDoc
		 */
		public function copySessionState(source:ILinkableObject, destination:ILinkableObject):void
		{
			var sessionState:Object = getSessionState(source);
			setSessionState(destination, sessionState, true);
		}
		
		private function applyDiff(base:Object, diff:Object):Object
		{
			if (base == null || typeof(base) != 'object')
				return diff;
			
			for (var key:String in diff)
				base[key] = applyDiff(base[key], diff[key]);
			
			return base;
		}

		/**
		 * @inheritDoc
		 */
		public function setSessionState(linkableObject:ILinkableObject, newState:Object, removeMissingDynamicObjects:Boolean = true):void
		{
			if (linkableObject == null)
			{
				reportError("SessionManager.setSessionState(): linkableObject cannot be null.");
				return;
			}

			// special cases:
			if (linkableObject is ILinkableVariable)
			{
				var lv:ILinkableVariable = linkableObject as ILinkableVariable;
				if (removeMissingDynamicObjects == false && newState && getQualifiedClassName(newState) == 'Object')
				{
					lv.setSessionState(applyDiff(ObjectUtil.copy(lv.getSessionState()), newState));
				}
				else
				{
					lv.setSessionState(newState);
				}
				return;
			}
			if (linkableObject is ILinkableCompositeObject)
			{
				if (newState is String)
					newState = [newState];
				
				if (newState != null && !(newState is Array))
				{
					var array:Array = [];
					for (var key:String in newState)
						array.push(new DynamicState(key, null, newState[key]));
					newState = array;
				}
				
				(linkableObject as ILinkableCompositeObject).setSessionState(newState as Array, removeMissingDynamicObjects);
				return;
			}

			if (newState == null)
				return;

			// delay callbacks before setting session state
			var objectCC:ICallbackCollection = getCallbackCollection(linkableObject);
			objectCC.delayCallbacks();

			var name:String;
			
			// cache property names if necessary
			var classQName:String = getQualifiedClassName(linkableObject);
			if (!classNameToSessionedPropertyNames[classQName])
				cacheClassInfo(linkableObject, classQName);
			var deprecatedLookup:Object = classNameToDeprecatedGetterLookup[classQName];
			
			// set session state
			for each (name in classNameToSessionedPropertyNames[classQName])
			{
				if (!newState.hasOwnProperty(name))
					continue;
				
				var property:ILinkableObject = null;
				try
				{
					property = linkableObject[name] as ILinkableObject;
				}
				catch (e:Error)
				{
					trace('SessionManager.setSessionState(): Unable to get property "'+name+'" of class "'+getQualifiedClassName(linkableObject)+'"',e.getStackTrace());
				}

				if (property == null)
					continue;

				// unless it's a deprecated property (for backwards compatibility), skip this property if it should not appear in the session state
				if (!deprecatedLookup[name])
					if (childToParentDictionaryMap[property] === undefined || !childToParentDictionaryMap[property][linkableObject])
						continue;
					
				setSessionState(property, newState[name], removeMissingDynamicObjects);
			}
			
			// pass deprecated session state to deprecated setters
			for each (name in classNameToDeprecatedSetterNames[classQName])
			{
				if (newState.hasOwnProperty(name) && newState[name] !== null)
				{
					_deprecatedSetterShouldRemoveMissingDynamicObjects = removeMissingDynamicObjects;
					linkableObject[name] = newState[name];
				}
			}
			
			// resume callbacks after setting session state
			objectCC.resumeCallbacks();
		}
		
		private var _deprecatedSetterShouldRemoveMissingDynamicObjects:Boolean;
		
		/**
		 * You can check this value when defining deprecated setter functions for backwards compatibility.
		 * @return true if SessionManager is currently applying a diff.
		 */		
		public function get deprecatedSetterShouldRemoveMissingDynamicObjects():Boolean
		{
			return _deprecatedSetterShouldRemoveMissingDynamicObjects;
		}
		
		private const _getSessionStateIgnoreList:Dictionary = new Dictionary(true); // keeps track of which objects are currently being traversed
		
		/**
		 * @inheritDoc
		 */
		public function getSessionState(linkableObject:ILinkableObject):Object
		{
			if (linkableObject == null)
			{
				reportError("SessionManager.getSessionState(): linkableObject cannot be null.");
				return null;
			}
			
			var result:Object = null;
			
			// special cases (explicit session state)
			if (linkableObject is ILinkableVariable)
			{
				result = (linkableObject as ILinkableVariable).getSessionState();
			}
			else if (linkableObject is ILinkableCompositeObject)
			{
				result = (linkableObject as ILinkableCompositeObject).getSessionState();
			}
			else
			{
				// implicit session state
				// first pass: get property names
				
				// cache property names if necessary
				var classQName:String = getQualifiedClassName(linkableObject);
				if (!classNameToSessionedPropertyNames[classQName])
					cacheClassInfo(linkableObject, classQName);
				
				var propertyNames:Array = classNameToSessionedPropertyNames[classQName];
				var deprecatedLookup:Object = classNameToDeprecatedGetterLookup[classQName];
				var resultNames:Array = [];
				var resultProperties:Array = [];
				var property:ILinkableObject = null;
				var i:int;
				//trace("getting session state for "+getQualifiedClassName(sessionedObject),"propertyNames="+propertyNames);
				for (i = 0; i < propertyNames.length; i++)
				{
					var name:String = propertyNames[i];
					// exclude deprecated properties from session state
					if (deprecatedLookup[name])
						continue;
					try
					{
						property = null; // must set this to null first because accessing the property may fail
						property = linkableObject[name] as ILinkableObject;
					}
					catch (e:Error)
					{
						reportError('Unable to get property "'+name+'" of class "'+getQualifiedClassName(linkableObject)+'"');
					}
					// first pass: set result[name] to the ILinkableObject
					if (property != null && !_getSessionStateIgnoreList[property])
					{
						// skip this property if it should not appear in the session state under the parent.
						if (childToParentDictionaryMap[property] === undefined || !childToParentDictionaryMap[property][linkableObject])
							continue;
						// avoid infinite recursion in implicit session states
						_getSessionStateIgnoreList[property] = true;
						resultNames.push(name);
						resultProperties.push(property);
					}
					else
					{
						/*
						if (property != null)
							trace("ignoring duplicate object:",name,property);
						*/
					}
				}
				// special case if there are no child objects -- return null
				if (resultNames.length > 0)
				{
					// second pass: get values from property names
					result = new Object();
					for (i = 0; i < resultNames.length; i++)
					{
						var value:Object = getSessionState(resultProperties[i]);
						property = resultProperties[i] as ILinkableObject;
						// do not include objects that have a null implicit session state (no child objects)
						if (value == null && !(property is ILinkableVariable) && !(property is ILinkableCompositeObject))
							continue;
						result[resultNames[i]] = value;
						//trace("getState",getQualifiedClassName(sessionedObject),resultNames[i],result[resultNames[i]]);
					}
				}
			}
			
			_getSessionStateIgnoreList[linkableObject] = undefined;
			
			return result;
		}
		
		/**
		 * This maps a qualified class name to an Array of names of sessioned properties contained in that class.
		 */
		private const classNameToSessionedPropertyNames:Object = new Object();
		/**
		 * This maps a qualified class name to an Array of names of deprecated setter functions contained in that class.
		 */
		private const classNameToDeprecatedSetterNames:Object = new Object();
		/**
		 * This maps a qualified class name to an Object mapping deprecated sessioned property names to true.
		 */
		private const classNameToDeprecatedGetterLookup:Object = new Object();
		
		/**
		 * avmplus.describeTypeJSON(o:*, flags:uint):Object
		 */		
		private const describeTypeJSON:Function = DescribeType.getJSONFunction();
		
		private function cacheClassInfo(linkableObject:ILinkableObject, classQName:String):void
		{
			// linkable property names
			var propertyNames:Array = [];
			var deprecatedSetters:Array = [];
			var deprecatedGetterLookup:Object = {}; // deprecated getter name -> true
			// iterate over the public properties, saving the names of the ones that implement ILinkableObject
			var type:Object = describeTypeJSON(linkableObject, DescribeType.INCLUDE_TRAITS | DescribeType.INCLUDE_ACCESSORS | DescribeType.INCLUDE_VARIABLES | DescribeType.INCLUDE_METADATA);
			var traits:Object = type.traits;
			for (var i:int = 0; i < 2; i++)
			{
				var variables:Array = i == 0 ? traits.accessors : traits.variables;
				for each (var variable:Object in variables)
				{
					var deprecated:Boolean = false;
					for each (var metadata:Object in variable.metadata)
					{
						if (metadata.name == 'Deprecated')
						{
							deprecated = true;
							break;
						}
					}
					
					if (variable.access == 'writeonly')
					{
						if (deprecated)
							deprecatedSetters.push(variable.name);
					}
					else if (ClassUtils.classImplements(variable.type, ILinkableObjectQualifiedClassName))
					{
						if (deprecated)
							deprecatedGetterLookup[variable.name] = true;
						propertyNames.push(variable.name);
					}
				}
			}
			
			AsyncSort.sortImmediately(propertyNames);
			AsyncSort.sortImmediately(deprecatedSetters);
			
			classNameToSessionedPropertyNames[classQName] = propertyNames;
			classNameToDeprecatedSetterNames[classQName] = deprecatedSetters;
			classNameToDeprecatedGetterLookup[classQName] = deprecatedGetterLookup;
		}

		/**
		 * This function gets a list of sessioned property names so accessor functions for non-sessioned properties do not have to be called.
		 * @param linkableObject An object containing sessioned properties.
		 * @return An Array containing the names of the sessioned properties of that object class.
		 */
		public function getLinkablePropertyNames(linkableObject:ILinkableObject):Array
		{
			if (linkableObject == null)
			{
				reportError("SessionManager.getLinkablePropertyNames(): linkableObject cannot be null.");
				return [];
			}

			var className:String = getQualifiedClassName(linkableObject);
			var propertyNames:Array = classNameToSessionedPropertyNames[className] as Array;
			if (propertyNames == null)
			{
				cacheClassInfo(linkableObject, className);
				propertyNames = classNameToSessionedPropertyNames[className] as Array;
			}
			return propertyNames;
		}
		
		internal static const ILinkableObjectQualifiedClassName:String = getQualifiedClassName(ILinkableObject);
		
		/**
		 * This maps a parent ILinkableObject to a Dictionary, which maps each child ILinkableObject it owns to a value of true.
		 */
		private const ownerToChildDictionaryMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a child ILinkableObject to its registered owner.
		 */
		private const childToOwnerMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a child ILinkableObject to a Dictionary, which maps each of its registered parent ILinkableObjects to a value of true if the child should appear in the session state automatically or false if not.
		 * Example: childToParentDictionaryMap[child][parent] == true
		 */
		private const childToParentDictionaryMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a parent ILinkableObject to a Dictionary, which maps each of its registered child ILinkableObjects to a value of true if the child should appear in the session state automatically or false if not.
		 * Example: parentToChildDictionaryMap[parent][child] == true
		 */
		private const parentToChildDictionaryMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		
		/**
		 * @inheritDoc
		 */
		public function getLinkableDescendants(root:ILinkableObject, filter:Class = null):Array
		{
			if (root == null)
			{
				reportError("SessionManager.getLinkableDescendants(): root cannot be null.");
				return [];
			}
			
			var result:Array = [];
			internalGetDescendants(result, root, filter, new Dictionary(true), int.MAX_VALUE);
			// don't include root object
			if (result.length > 0 && result[0] == root)
				result.shift();
			return result;
		}
		private function internalGetDescendants(output:Array, root:ILinkableObject, filter:Class, ignoreList:Dictionary, depth:int):void
		{
			if (root == null || ignoreList[root] !== undefined)
				return;
			ignoreList[root] = true;
			if (filter == null || root is filter)
				output.push(root);
			if (--depth <= 0)
				return;
			
			for (var object:Object in parentToChildDictionaryMap[root])
			{
				internalGetDescendants(output, object as ILinkableObject, filter, ignoreList, depth);
			}
		}
		
		private const _dTaskStackTrace:Dictionary = new Dictionary(false);
		private const _d2dOwnerTask:Dictionary2D = new Dictionary2D(true, false); // task cannot use weak pointer because it may be a function
		private const _d2dTaskOwner:Dictionary2D = new Dictionary2D(false, true); // task cannot use weak pointer because it may be a function
		private const _dBusyTraversal:Dictionary = new Dictionary(true); // ILinkableObject -> Boolean
		private const _aBusyTraversal:Array = [];
		private const _dUnbusyTriggerCounts:Dictionary = new Dictionary(true); // ILinkableObject -> int
		private const _dUnbusyStackTraces:Dictionary = new Dictionary(true); // ILinkableObject -> String
		
		private function disposeBusyTaskPointers(disposedObject:ILinkableObject):void
		{
			_d2dOwnerTask.removeAllPrimary(disposedObject);
			_d2dTaskOwner.removeAllSecondary(disposedObject);
		}
		
		/**
		 * Returns a mapping from owner debugId to an Array of debugIds for its busy tasks.
		 */
		public function debugBusyObjects():Object
		{
			var result:Object = {};
			for (var owner:* in _d2dOwnerTask.dictionary)
			{
				var tasks:Array = [];
				for (var task:* in _d2dOwnerTask.dictionary[owner])
					tasks.push(debugId(task));
				
				result[debugId(owner)] = tasks;
			}
			return result;
		}
		
		/**
		 * @inheritDoc
		 */
		public function assignBusyTask(taskToken:Object, busyObject:ILinkableObject):void
		{
			if (debugBusyTasks)
				_dTaskStackTrace[taskToken] = new Error("Stack trace when task was last assigned").getStackTrace();
			
			// stop if already assigned
			var test:* = _d2dTaskOwner.dictionary[taskToken];
			if (test && test[busyObject])
				return;
			
			if (taskToken is AsyncToken && !WeaveAPI.ProgressIndicator.hasTask(taskToken))
				(taskToken as AsyncToken).addResponder(new AsyncResponder(unassignAsyncToken, unassignAsyncToken, taskToken));
			
			_d2dOwnerTask.set(busyObject, taskToken, true);
			_d2dTaskOwner.set(taskToken, busyObject, true);
		}
		
		private function unassignAsyncToken(event:Event, token:AsyncToken):void
		{
			unassignBusyTask(token);
		}
		
		/**
		 * @inheritDoc
		 */
		public function unassignBusyTask(taskToken:Object):void
		{
			if (WeaveAPI.ProgressIndicator.hasTask(taskToken))
			{
				WeaveAPI.ProgressIndicator.removeTask(taskToken);
				return;
			}
			
			var dOwner:Dictionary = _d2dTaskOwner.dictionary[taskToken];
			if (!dOwner)
				return;
			
			delete _d2dTaskOwner.dictionary[taskToken];
			nextOwner: for (var owner:* in dOwner)
			{
				var dTask:Dictionary = _d2dOwnerTask.dictionary[owner];
				delete dTask[taskToken];
				
				// if there are other tasks, continue to next owner
				for (var task:* in dTask)
					continue nextOwner;
				
				// when there are no more tasks, check later to see if callbacks trigger
				_dUnbusyTriggerCounts[owner] = getCallbackCollection(owner).triggerCounter;
				WeaveAPI.StageUtils.startTask(null, unbusyTrigger, WeaveAPI.TASK_PRIORITY_0_IMMEDIATE);
				
				if (debugBusyTasks)
				{
					var stackTrace:String = new Error("Stack trace when last task was unassigned").getStackTrace();
					_dUnbusyStackTraces[owner] = {assigned: _dTaskStackTrace[taskToken], unassigned: stackTrace, token: taskToken};
				}
			}
		}
		
		/**
		 * Called the frame after an owner's last busy task is unassigned.
		 * Triggers callbacks if they have not been triggered since then.
		 */
		private function unbusyTrigger(stopTime:int):Number
		{
			var owner:*;
			do {
				if (getTimer() > stopTime)
					return 0;
				
				owner = null;
				for (owner in _dUnbusyTriggerCounts)
				{
					var triggerCount:int = _dUnbusyTriggerCounts[owner];
					delete _dUnbusyTriggerCounts[owner]; // affects next for loop iteration - mitigated by outer loop
					
					var cc:CallbackCollection = CallbackCollection(getCallbackCollection(owner));
					if (cc.wasDisposed)
						continue; // already disposed
					
					if (cc.triggerCounter != triggerCount)
						continue; // already triggered
					
					if (linkableObjectIsBusy(owner))
						continue; // busy again
					
					if (debugBusyTasks)
					{
						var stackTraces:Object = _dUnbusyStackTraces[owner];
						trace('Triggering callbacks because they have not triggered since owner has becoming unbusy:', debugId(owner));
						trace(stackTraces.assigned);
						trace(stackTraces.unassigned);
					}
					
					cc.triggerCallbacks();
				}
			} while (owner);
			
			return 1;
		}
		
		/**
		 * @inheritDoc
		 */
		public function linkableObjectIsBusy(linkableObject:ILinkableObject):Boolean
		{
			var busy:Boolean = false;
			
			_aBusyTraversal.push(linkableObject);
			_dBusyTraversal[linkableObject] = true;
			
			outerLoop: for (var i:int = 0; i < _aBusyTraversal.length; i++)
			{
				linkableObject = _aBusyTraversal[i] as ILinkableObject;
				
				if (linkableObject is ILinkableObjectWithBusyStatus)
				{
					if ((linkableObject as ILinkableObjectWithBusyStatus).isBusy())
					{
						busy = true;
						break;
					}
					// do not check children
					continue;
				}
				
				// if the object is assigned a task, it's busy
				for (var task:Object in _d2dOwnerTask.dictionary[linkableObject])
				{
					if (debugBusyTasks)
					{
						var stackTrace:String = _dTaskStackTrace[task];
						//trace(stackTrace);
					}
					busy = true;
					break outerLoop;
				}
				
				// see if children are busy
				var dChild:Dictionary = parentToChildDictionaryMap[linkableObject];
				for (var child:Object in dChild)
				{
					// queue all the children that haven't been queued yet
					if (!_dBusyTraversal[child])
					{
						_aBusyTraversal.push(child);
						_dBusyTraversal[child] = true;
					}
				}
			}
			
			// reset traversal dictionary for next time
			for each (linkableObject in _aBusyTraversal)
				_dBusyTraversal[linkableObject] = false;
			
			// reset traversal queue for next time
			_aBusyTraversal.length = 0;
			
			return busy;
		}
		
		
		/**
		 * This maps an ILinkableObject to a ICallbackCollection associated with it.
		 */
		private const linkableObjectToCallbackCollectionMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly

		/**
		 * @inheritDoc
		 */
		public function getCallbackCollection(linkableObject:ILinkableObject):ICallbackCollection
		{
			if (linkableObject == null)
				return null;
			
			if (linkableObject is ICallbackCollection)
				return linkableObject as ICallbackCollection;
			
			var objectCC:ICallbackCollection = linkableObjectToCallbackCollectionMap[linkableObject] as ICallbackCollection;
			if (objectCC == null)
			{
				objectCC = registerDisposableChild(linkableObject, new CallbackCollection());
				if (CallbackCollection.debug)
					(objectCC as CallbackCollection)._linkableObject = linkableObject;
				linkableObjectToCallbackCollectionMap[linkableObject] = objectCC;
				
				// Make sure UIComponents get registered with linkable owners because MXML developers
				// may forget to do so, since it's not simple or intuitive in MXML.
				if (linkableObject is UIComponent)
				{
					var component:UIComponent = linkableObject as UIComponent;
					if (!_registerUIComponent(component))
						component.addEventListener(Event.ADDED, _registerUIComponentLater);
				}
			}
			return objectCC;
		}
		
		/**
		 * This function is an event listener that in turn calls _registerUIComponent.
		 * @param event The event dispatched by the UIComponent to be passed to _registerUIComponent.
		 */
		private function _registerUIComponentLater(event:Event):void
		{
			if (event.target == event.currentTarget)
			{
				var component:UIComponent = event.currentTarget as UIComponent;
				if (_registerUIComponent(component))
					component.removeEventListener(event.type, _registerUIComponentLater, event.eventPhase == EventPhase.CAPTURING_PHASE);
			}
		}
		
		/**
		 * This function will register a UIComponent/ILinkableObject as a disposable child of an ancestral
		 * DisplayObjectContainer/ILinkableObject if it has no linkable owner yet.  This makes sure that the
		 * component is disposed of when its ancestor is disposed of.
		 * @param linkableComponent A UIComponent that implements ILinkableObject.
		 * @return true if the component has a linkable owner, either before or after this function is called, or if the object was disposed.
		 */
		private function _registerUIComponent(linkableComponent:UIComponent):Boolean
		{
			if (objectWasDisposed(linkableComponent))
				return true; // so the event listener will be removed
			
			var owner:ILinkableObject = childToOwnerMap[linkableComponent] as ILinkableObject;
			if (owner == null)
			{
				var parent:DisplayObjectContainer = linkableComponent.parent;
				while (parent)
				{
					if (parent is ILinkableObject)
					{
						registerDisposableChild(parent, linkableComponent);
						return true; // component has a linkable owner now
					}
					parent = parent.parent;
				}
				return false; // component does not have a linkable owner yet
			}
			return true; // component already has a linkable owner
		}

		/**
		 * @inheritDoc
		 */
		public function objectWasDisposed(object:Object):Boolean
		{
			if (object == null)
				return false;
			if (object is ILinkableObject)
			{
				var cc:CallbackCollection = getCallbackCollection(object as ILinkableObject) as CallbackCollection;
				if (cc)
					return cc.wasDisposed;
			}
			return _disposedObjectsMap[object] !== undefined;
		}
		
		private const _disposedObjectsMap:Dictionary = new Dictionary(true); // weak keys to be gc-friendly
		
		private static const DISPOSE:String = "dispose"; // this is the name of the dispose() function.

		/**
		 * @inheritDoc
		 */
		public function disposeObject(object:Object):void
		{
			if (object != null && !_disposedObjectsMap[object])
			{
				_disposedObjectsMap[object] = true;
				
				// clean up pointers to busy tasks
				disposeBusyTaskPointers(object as ILinkableObject);
				
				try
				{
					// if the object implements IDisposableObject, call its dispose() function now
					if (object is IDisposableObject)
					{
						(object as IDisposableObject).dispose();
					}
					else if (object.hasOwnProperty(DISPOSE))
					{
						// call dispose() anyway if it exists, because it is common to forget to implement IDisposableObject.
						object[DISPOSE]();
					}
				}
				catch (e:Error)
				{
					reportError(e);
				}
				
				var linkableObject:ILinkableObject = object as ILinkableObject;
				if (linkableObject)
				{
					// dispose of the callback collection corresponding to the object.
					// this removes all callbacks, including the one that triggers parent callbacks.
					var objectCC:ICallbackCollection = getCallbackCollection(linkableObject);
					if (objectCC != linkableObject)
						disposeObject(objectCC);
					
					// unregister from parents
					if (childToParentDictionaryMap[linkableObject] !== undefined)
					{
						// remove the parent-to-child mappings
						for (var parent:Object in childToParentDictionaryMap[linkableObject])
							if (parentToChildDictionaryMap[parent] !== undefined)
								delete parentToChildDictionaryMap[parent][linkableObject];
						// remove child-to-parent mapping
						delete childToParentDictionaryMap[linkableObject];
					}
		
					// unregister from owner
					var owner:ILinkableObject = childToOwnerMap[linkableObject] as ILinkableObject;
					if (owner != null)
					{
						if (ownerToChildDictionaryMap[owner] !== undefined)
							delete ownerToChildDictionaryMap[owner][linkableObject];
						delete childToOwnerMap[linkableObject];
					}
		
					// if the object is an ILinkableVariable, unlink it from all bindable properties that were previously linked
					if (linkableObject is ILinkableVariable)
						for (var bindableParent:* in _watcherMap[linkableObject])
							for (var bindablePropertyName:String in _watcherMap[linkableObject][bindableParent])
								unlinkBindableProperty(linkableObject as ILinkableVariable, bindableParent, bindablePropertyName);
					
					// unlink this object from all other linkable objects
					for (var otherObject:Object in linkFunctionCache.dictionary[linkableObject])
						unlinkSessionState(linkableObject, otherObject as ILinkableObject);
					
					// dispose of all registered children that this object owns
					var children:Dictionary = ownerToChildDictionaryMap[linkableObject] as Dictionary;
					if (children != null)
					{
						// clear the pointers to the child dictionaries for this object
						delete ownerToChildDictionaryMap[linkableObject];
						delete parentToChildDictionaryMap[linkableObject];
						// dispose of the children this object owned
						for (var child:Object in children)
							disposeObject(child);
					}
					
					// FOR DEBUGGING PURPOSES
					if (Capabilities.isDebugger)
					{
						var error:Error = new Error("This is the stack trace from when the object was previously disposed.");
						objectCC.addImmediateCallback(null, function():void { debugDisposedObject(linkableObject, error); } );
					}
				}
				
				var displayObject:DisplayObject = object as DisplayObject;
				if (displayObject)
				{
					// remove this DisplayObject from its parent
					var parentContainer:DisplayObjectContainer = displayObject.parent;
					try
					{
						if (parentContainer && parentContainer == displayObject.parent)
							parentContainer.removeChild(displayObject);
					}
					catch (e:Error)
					{
						// an error may occur if removeChild() is called twice.
					}
					parentContainer = displayObject as DisplayObjectContainer;
					if (parentContainer)
					{
						// Removing all children fixes errors that may occur in the next
						// frame related to callLaterDispatcher and validateDisplayList.
						var n:int = parentContainer.numChildren;
						while (n > 0)
						{
							try {
								parentContainer.removeChildAt(n--);
							} catch (e:Error) { }
						}
					}
					if (displayObject is UIComponent)
						(displayObject as UIComponent).mx_internal::cancelAllCallLaters();
				}
			}
		}
		
		// FOR DEBUGGING PURPOSES
		private function debugDisposedObject(disposedObject:ILinkableObject, disposedError:Error):void
		{
			// set some variables to aid in debugging - only useful if you add a breakpoint here.
			var obj:*;
			var ownerPath:Array = []; while (obj = getLinkableOwner(obj)) { ownerPath.unshift(obj); }
			var parents:Array = []; for (obj in childToParentDictionaryMap[disposedObject]) { parents.push(obj); }
			var children:Array = []; for (obj in parentToChildDictionaryMap[disposedObject]) { children.push(obj); }
			var sessionState:Object = getSessionState(disposedObject);

			// ADD A BREAKPOINT HERE TO DIAGNOSE THE PROBLEM
			var msg:String = "WARNING: An object triggered callbacks after previously being disposed. " + debugId(disposedObject);
			if (disposedObject is ILinkableVariable)
				msg += ' (value = ' + (disposedObject as ILinkableVariable).getSessionState() + ')';
			reportError(disposedError);
			reportError(msg);
		}

		/**
		 * @private
		 * For debugging only.
		 */
		public function _getOwnerPath(descendant:ILinkableObject):Array
		{
			var result:Array = [descendant];
			while (descendant && descendant != WeaveAPI.globalHashMap)
				result.unshift(debugId(descendant = getLinkableOwner(descendant)));
			if (!descendant)
				result.unshift(result[result.length - 1] + " is not a descendant of " + debugId(WeaveAPI.globalHashMap));
			return result;
		}
		
		/**
		 * @private
		 * For debugging only.
		 */
		public function _getPaths(root:ILinkableObject, descendant:ILinkableObject):Array
		{
			var results:Array = [];
			for (var parent:Object in childToParentDictionaryMap[descendant])
			{
				var name:String = _getChildPropertyName(parent as ILinkableObject, descendant);
				if (name != null)
				{
					// this parent may be the one we want
					var result:Array = _getPaths(root, parent as ILinkableObject);
					if (result != null)
					{
						result.push(name);
						results.push(result);
					}
				}
			}
			if (results.length == 0)
				return root == null ? results : null;
			return results;
		}

		/**
		 * internal use only
		 */
		private function _getChildPropertyName(parent:ILinkableObject, child:ILinkableObject):String
		{
			if (parent is ILinkableHashMap)
				return (parent as ILinkableHashMap).getName(child);

			// find the property name that returns the child
			for each (var name:String in getLinkablePropertyNames(parent))
				if (parent[name] == child)
					return name;
			return null;
		}
		
		/**
		 * @inheritDoc
		 */
		public function getPath(root:ILinkableObject, descendant:ILinkableObject):Array
		{
			var tree:Object = getSessionStateTree(root, null);
			var path:Array = _getPath(tree, descendant);
			return path;
		}
		private function _getPath(tree:Object, descendant:ILinkableObject):Array
		{
			if (tree[TREE_OBJECT] == descendant)
				return [];
			for each (var child:Object in tree[TREE_CHILDREN])
			{
				var path:Array = _getPath(child, descendant);
				if (path)
				{
					path.unshift(child[TREE_LABEL]);
					return path;
				}
			}
			return null;
		}
		
		/**
		 * @inheritDoc
		 */
		public function getObject(root:ILinkableObject, path:Array):ILinkableObject
		{
			var object:ILinkableObject = root;
			for each (var propertyName:Object in path)
			{
				if (object == null)
					return null;
				if (object is ILinkableHashMap)
				{
					if (propertyName is Number)
						object = (object as ILinkableHashMap).getObjects()[propertyName];
					else
						object = (object as ILinkableHashMap).getObject(String(propertyName));
				}
				else if (object is ILinkableDynamicObject)
				{
					// ignore propertyName and always return the internalObject
					object = (object as ILinkableDynamicObject).internalObject;
				}
				else
				{
					if (getLinkablePropertyNames(object).indexOf(propertyName) < 0)
						return null;
					object = object[propertyName] as ILinkableObject;
				}
			}
			return object;
		}
		
		
		
		
		
		
		/**************************************
		 * linking sessioned objects together
		 **************************************/





		/**
		 * This maps destination and source ILinkableObjects to a function like:
		 *     function():void { setSessionState(destination, getSessionState(source), true); }
		 */
		private const linkFunctionCache:Dictionary2D = new Dictionary2D(true, true);
		/**
		 * @inheritDoc
		 */
		public function linkSessionState(primary:ILinkableObject, secondary:ILinkableObject):void
		{
			if (primary == null || secondary == null)
			{
				reportError("SessionManager.linkSessionState(): Parameters to this function cannot be null.");
				return;
			}
			if (primary == secondary)
			{
				reportError("Warning! Attempt to link session state of an object with itself");
				return;
			}
			if (linkFunctionCache.get(primary, secondary) is Function)
				return; // already linked
			
			if (CallbackCollection.debug)
				var stackTrace:String = new Error().getStackTrace();
				
			var setPrimary:Function = function():void { setSessionState(primary, getSessionState(secondary), true); };
			var setSecondary:Function = function():void { setSessionState(secondary, getSessionState(primary), true); };
			
			linkFunctionCache.set(primary, secondary, setPrimary);
			linkFunctionCache.set(secondary, primary, setSecondary);
			
			// when secondary changes, copy from secondary to primary
			getCallbackCollection(secondary).addImmediateCallback(primary, setPrimary);
			// when primary changes, copy from primary to secondary
			getCallbackCollection(primary).addImmediateCallback(secondary, setSecondary, true); // copy from primary now
		}
		/**
		 * @inheritDoc
		 */
		public function unlinkSessionState(first:ILinkableObject, second:ILinkableObject):void
		{
			if (first == null || second == null)
			{
				reportError("SessionManager.unlinkSessionState(): Parameters to this function cannot be null.");
				return;
			}
			
			var setFirst:Function = linkFunctionCache.remove(first, second) as Function;
			var setSecond:Function = linkFunctionCache.remove(second, first) as Function;
			
			getCallbackCollection(second).removeCallback(setFirst);
			getCallbackCollection(first).removeCallback(setSecond);
		}





		/******************************************************
		 * linking sessioned objects with bindable properties
		 ******************************************************/
		
		private const VALUE_NOT_ACCEPTED:String = lang('Value not accepted.'); // errorString used by linkBindableProperty
		
		/*private function debugLink(linkVal:Object, bindVal:Object, useLinkableBefore:Boolean, useLinkableAfter:Boolean, callingLater:Boolean):void
		{
			var link:String = (useLinkableBefore && useLinkableAfter ? 'LINK' : 'link') + '(' + ObjectUtil.toString(linkVal) + ')';
			var bind:String = (!useLinkableBefore && !useLinkableAfter ? 'BIND' : 'bind') + '(' + ObjectUtil.toString(bindVal) + ')';
			var str:String = link + ', ' + bind;
			if (useLinkableBefore && !useLinkableAfter)
				str = link + ' = ' + bind;
			if (!useLinkableBefore && useLinkableAfter)
				str = bind + ' = ' + link;
			if (callingLater)
				str += ' (callingLater)';
			
			trace(str);
		}*/
		
		/**
		 * @inheritDoc
		 */
		public function linkBindableProperty(linkableVariable:ILinkableVariable, bindableParent:Object, bindablePropertyName:String, delay:uint = 0, onlyWhenFocused:Boolean = false):void
		{
			if (linkableVariable == null || bindableParent == null || bindablePropertyName == null)
			{
				reportError("linkBindableProperty(): Parameters to this function cannot be null.");
				return;
			}
			
			if (!bindableParent.hasOwnProperty(bindablePropertyName))
			{
				reportError('linkBindableProperty(): Unable to access property "'+bindablePropertyName+'" in class '+getQualifiedClassName(bindableParent));
				return;
			}
			
			// unlink in case previously linked
			unlinkBindableProperty(linkableVariable, bindableParent, bindablePropertyName);
			
			// initialize dictionaries
			if (_watcherMap[linkableVariable] === undefined)
				_watcherMap[linkableVariable] = new Dictionary(true);
			if (_watcherMap[linkableVariable][bindableParent] === undefined)
				_watcherMap[linkableVariable][bindableParent] = new Object();
			
			var callbackCollection:ICallbackCollection = getCallbackCollection(linkableVariable);
			var watcher:ChangeWatcher = null;
			var useLinkableValue:Boolean = true;
			var callLaterTime:int = 0;
			var uiComponent:UIComponent = bindableParent as UIComponent;
			var recursiveCall:Boolean = false;
			// a function that takes zero parameters and sets the bindable value.
			var synchronize:Function = function(firstParam:* = undefined, callingLater:Boolean = false):void
			{
				// unlink if linkableVariable was disposed
				if (objectWasDisposed(linkableVariable))
				{
					unlinkBindableProperty(linkableVariable, bindableParent, bindablePropertyName);
					return;
				}
				// stop if unlinked
				var test:Object;
				if (!(test = _watcherMap[linkableVariable]) || !(test = test[bindableParent]) || !test.hasOwnProperty(bindablePropertyName))
					return;
				
				/*debugLink(
					linkableVariable.getSessionState(),
					firstParam===undefined ? bindableParent[bindablePropertyName] : firstParam,
					useLinkableValue,
					firstParam===undefined,
					callingLater
				);*/
				
				// If bindableParent has focus:
				// When linkableVariable changes, update bindable value only when focus is lost (callLaterTime = int.MAX_VALUE).
				// When bindable value changes, update linkableVariable after a delay.
				
				if (!callingLater)
				{
					// remember which value changed last -- the linkable one or the bindable one
					useLinkableValue = firstParam === undefined; // true when called from linkable variable grouped callback
					// if we're not calling later and there is already a timestamp, just wait for the callLater to trigger
					if (callLaterTime)
					{
						// if there is a callLater waiting to trigger, update the target time
						callLaterTime = useLinkableValue ? int.MAX_VALUE : getTimer() + delay;
						
						//trace('\tdelaying the timer some more');
						
						return;
					}
				}
				
				// if the bindable value is not a boolean and the bindable parent has focus, delay synchronization
				var bindableValue:Object = bindableParent[bindablePropertyName];
				if (!(bindableValue is Boolean))
				{
					if (uiComponent)
					{
						var obj:DisplayObject = uiComponent.getFocus();
						if (obj && uiComponent.contains(obj)) // has focus
						{
							if (linkableVariable is LinkableVariable)
							{
								if ((linkableVariable as LinkableVariable).verifyValue(bindableValue))
								{
									// clear previous error string
									if (uiComponent.errorString == VALUE_NOT_ACCEPTED)
										uiComponent.errorString = '';
								}
								else
								{
									// show error string if not already shown
									if (!uiComponent.errorString)
										uiComponent.errorString = VALUE_NOT_ACCEPTED;
								}
							}
							
							var currentTime:int = getTimer();
							
							// if we're not calling later, set the target time (int.MAX_VALUE means delay until focus is lost)
							if (!callingLater)
								callLaterTime = useLinkableValue ? int.MAX_VALUE : currentTime + delay;
							
							// if we haven't reached the target time yet or callbacks are delayed, call later
							if (currentTime < callLaterTime)
							{
								uiComponent.callLater(synchronize, [firstParam, true]);
								return;
							}
						}
						else if (onlyWhenFocused && !callingLater)
						{
							// component does not have focus, so ignore the bindableValue.
							return;
						}
						
						// otherwise, synchronize now
						// clear saved time stamp when we are about to synchronize
						callLaterTime = 0;
					}
				}
				
				// if the linkable variable's callbacks are delayed, delay synchronization
				if (getCallbackCollection(linkableVariable).callbacksAreDelayed)
				{
					WeaveAPI.StageUtils.callLater(linkableVariable, synchronize, [firstParam, true], WeaveAPI.TASK_PRIORITY_0_IMMEDIATE);
					return;
				}
				
				// synchronize
				if (useLinkableValue)
				{
					var linkableValue:Object = linkableVariable.getSessionState();
					if ((bindableValue is Number) != (linkableValue is Number))
					{
						try {
							if (linkableValue is Number)
							{
								if (isNaN(linkableValue as Number))
									linkableValue = '';
								else
									linkableValue = '' + linkableValue;
							}
							else
							{
								linkableVariable.setSessionState(Number(linkableValue));
								linkableValue = linkableVariable.getSessionState();
							}
						} catch (e:Error) { }
					}
					if (bindableValue != linkableValue)
						bindableParent[bindablePropertyName] = linkableValue;
					
					// clear previous error string
					if (uiComponent && linkableVariable is LinkableVariable && uiComponent.errorString == VALUE_NOT_ACCEPTED)
						uiComponent.errorString = '';
				}
				else
				{
					var prevCount:uint = callbackCollection.triggerCounter;
					linkableVariable.setSessionState(bindableValue);
					// Always synchronize after setting the linkableVariable because there may
					// be constraints on the session state that will prevent the callbacks
					// from triggering if the bindable value does not match those constraints.
					// This makes UIComponents update to the real value after they lose focus.
					if (callbackCollection.triggerCounter == prevCount && !recursiveCall)
					{
						// avoid infinite recursion in the case where the new value is not accepted by a verifier function
						recursiveCall = true;
						synchronize();
						recursiveCall = false;
					}
				}
			};
			// Copy session state over to bindable property now, before calling BindingUtils.bindSetter(),
			// because that will copy from the bindable property to the sessioned property.
			_watcherMap[linkableVariable][bindableParent][bindablePropertyName] = null; // prevents synchronize() from thinking it's unlinked
			synchronize();
			watcher = BindingUtils.bindSetter(synchronize, bindableParent, bindablePropertyName);
			// save a mapping from the linkableVariable,bindableParent,bindablePropertyName parameters to the watcher for the property
			_watcherMap[linkableVariable][bindableParent][bindablePropertyName] = watcher;
			// when session state changes, set bindable property
			_watcherToSynchronizeFunctionMap[watcher] = synchronize;
			callbackCollection.addImmediateCallback(bindableParent, synchronize);
		}
		/**
		 * @inheritDoc
		 */
		public function unlinkBindableProperty(linkableVariable:ILinkableVariable, bindableParent:Object, bindablePropertyName:String):void
		{
			if (linkableVariable == null || bindableParent == null || bindablePropertyName == null)
			{
				reportError("unlinkBindableProperty(): Parameters to this function cannot be null.");
				return;
			}
			
			try
			{
				var watcher:ChangeWatcher = _watcherMap[linkableVariable][bindableParent][bindablePropertyName];
				var cc:ICallbackCollection = getCallbackCollection(linkableVariable);
				cc.removeCallback(_watcherToSynchronizeFunctionMap[watcher]);
				watcher.unwatch();
				delete _watcherMap[linkableVariable][bindableParent][bindablePropertyName];
			}
			catch (e:Error)
			{
				//trace(SessionManager, getQualifiedClassName(bindableParent), bindablePropertyName, e.getStackTrace());
			}
		}
		/**
		 * This is a multidimensional mapping, such that
		 *     _watcherMap[linkableVariable][bindableParent][bindablePropertyName]
		 * maps to a ChangeWatcher object.
		 */
		private const _watcherMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a ChangeWatcher object to a function that was added as a callback to the corresponding ILinkableVariable.
		 */
		private const _watcherToSynchronizeFunctionMap:Dictionary = new Dictionary(); // use weak links to be GC-friendly
		
		
		
		
		
		/*******************
		 * Computing diffs
		 *******************/
		
		
		public static const DIFF_DELETE:String = 'delete';
		
		/**
		 * @inheritDoc
		 */
		public function computeDiff(oldState:Object, newState:Object):*
		{
			var type:String = typeof(oldState); // the type of null is 'object'
			var diffValue:*;

			// special case if types differ
			if (typeof(newState) != type)
				return newState;
			
			if (type == 'xml')
			{
				throw new Error("XML is not supported as a primitive session state type.");
			}
			else if (type == 'number')
			{
				if (isNaN(oldState as Number) && isNaN(newState as Number))
					return undefined; // no diff
				
				if (oldState != newState)
					return newState;
				
				return undefined; // no diff
			}
			else if (oldState === null || newState === null || type != 'object') // other primitive value
			{
				if (oldState !== newState) // no type-casting
					return newState;
				
				return undefined; // no diff
			}
			else if (oldState is Array && newState is Array)
			{
				// If neither is a dynamic state array, don't compare them as such.
				if (!DynamicState.isDynamicStateArray(oldState) && !DynamicState.isDynamicStateArray(newState))
				{
					if (StandardLib.arrayCompare(oldState as Array, newState as Array) == 0)
						return undefined; // no diff
					return newState;
				}
				
				// create an array of new DynamicState objects for all new names followed by missing old names
				var i:int;
				var typedState:Object;
				var changeDetected:Boolean = false;
				
				// create oldLookup
				var oldLookup:Object = {};
				var objectName:String;
				var className:String;
				var sessionState:Object;
				for (i = 0; i < oldState.length; i++)
				{
					// assume everthing is typed session state
					//note: there is no error checking here for typedState
					typedState = oldState[i];
					objectName = typedState[DynamicState.OBJECT_NAME];
					// use '' instead of null to avoid "null"
					oldLookup[objectName || ''] = typedState;
				}
				if (oldState.length != newState.length)
					changeDetected = true;
				
				// create new Array with new DynamicState objects
				var result:Array = [];
				for (i = 0; i < newState.length; i++)
				{
					// assume everthing is typed session state
					//note: there is no error checking here for typedState
					typedState = newState[i];
					objectName = typedState[DynamicState.OBJECT_NAME];
					className = typedState[DynamicState.CLASS_NAME];
					sessionState = typedState[DynamicState.SESSION_STATE];
					var oldTypedState:Object = oldLookup[objectName || ''];
					delete oldLookup[objectName || '']; // remove it from the lookup because it's already been handled
					
					// If the object specified in newState does not exist in oldState, we don't need to do anything further.
					// If the class is the same as before, then we can save a diff instead of the entire session state.
					// If the class changed, we can't save only a diff -- we need to keep the entire session state.
					// Replace the sessionState in the new DynamicState object with the diff.
					if (oldTypedState != null && oldTypedState[DynamicState.CLASS_NAME] == className)
					{
						className = null; // no change
						diffValue = computeDiff(oldTypedState[DynamicState.SESSION_STATE], sessionState);
						if (diffValue === undefined)
						{
							// Since the class name is the same and the session state is the same,
							// we only need to specify that this name is still present.
							result.push(objectName);
							
							if (!changeDetected && oldState[i][DynamicState.OBJECT_NAME] != objectName)
								changeDetected = true;
							
							continue;
						}
						sessionState = diffValue;
					}
					
					// save in new array and remove from lookup
					result.push(new DynamicState(objectName || null, className, sessionState)); // convert empty string to null
					changeDetected = true;
				}
				
				// Anything remaining in the lookup does not appear in newState.
				// Add DynamicState entries with an invalid className ("delete") to convey that each of these objects should be removed.
				for (objectName in oldLookup)
				{
					result.push(new DynamicState(objectName || null, DIFF_DELETE)); // convert empty string to null
					changeDetected = true;
				}
				
				if (changeDetected)
					return result;
				
				return undefined; // no diff
			}
			else // nested object
			{
				var diff:* = undefined; // start with no diff
				
				// find old properties that changed value
				for (var oldName:String in oldState)
				{
					diffValue = computeDiff(oldState[oldName], newState[oldName]);
					if (diffValue !== undefined)
					{
						if (!diff)
							diff = {};
						diff[oldName] = diffValue;
					}
				}

				// find new properties
				for (var newName:String in newState)
				{
					if (oldState[newName] === undefined)
					{
						if (!diff)
							diff = {};
						diff[newName] = newState[newName]; // TODO: same object pointer.. potential problem?
					}
				}

				return diff;
			}
		}
		
		/**
		 * @inheritDoc
		 */
		public function combineDiff(baseDiff:Object, diffToAdd:Object):Object
		{
			var baseType:String = typeof(baseDiff); // the type of null is 'object'
			var diffType:String = typeof(diffToAdd);

			// special cases
			if (baseDiff == null || diffToAdd == null || baseType != diffType || baseType != 'object')
			{
				if (diffType == 'object') // not a primitive, so make a copy
					baseDiff = ObjectUtil.copy(diffToAdd);
				else
					baseDiff = diffToAdd;
			}
			else if (baseDiff is Array && diffToAdd is Array)
			{
				var i:int;
				
				// If either of the arrays look like DynamicState arrays, treat as such
				if (DynamicState.isDynamicStateArray(baseDiff) || DynamicState.isDynamicStateArray(diffToAdd))
				{
					var typedState:Object;
					var objectName:String;

					// create lookup: objectName -> old diff entry
					// temporarily turn baseDiff into an Array of object names
					var baseLookup:Object = {};
					for (i = 0; i < baseDiff.length; i++)
					{
						typedState = baseDiff[i];
						// note: no error checking for typedState
						if (typedState is String || typedState == null)
							objectName = typedState as String;
						else
							objectName = typedState[DynamicState.OBJECT_NAME] as String;
						baseLookup[objectName] = typedState;
						// temporarily turn baseDiff into an Array of object names
						baseDiff[i] = objectName;
					}
					// apply each typedState diff appearing in diffToAdd
					for (i = 0; i < diffToAdd.length; i++)
					{
						typedState = diffToAdd[i];
						// note: no error checking for typedState
						if (typedState is String || typedState == null)
							objectName = typedState as String;
						else
							objectName = typedState[DynamicState.OBJECT_NAME] as String;
						
						// adjust names list so this name appears at the end
						if (baseLookup.hasOwnProperty(objectName))
						{
							for (var j:int = (baseDiff as Array).indexOf(objectName); j < baseDiff.length - 1; j++)
								baseDiff[j] = baseDiff[j + 1];
							baseDiff[baseDiff.length - 1] = objectName;
						}
						else
						{
							baseDiff.push(objectName);
						}
						
						// apply diff
						var oldTypedState:Object = baseLookup[objectName];
						if (oldTypedState is String || oldTypedState == null)
						{
							if (typedState is String || typedState == null)
								baseLookup[objectName] = typedState; // avoid unnecessary function call overhead
							else
								baseLookup[objectName] = ObjectUtil.copy(typedState);
						}
						else if (!(typedState is String || typedState == null)) // update dynamic state
						{
							var className:String = typedState[DynamicState.CLASS_NAME];
							// if new className is different and not null, start with a fresh typedState diff
							if (className && className != oldTypedState[DynamicState.CLASS_NAME])
							{
								baseLookup[objectName] = ObjectUtil.copy(typedState);
							}
							else // className hasn't changed, so combine the diffs
							{
								oldTypedState[DynamicState.SESSION_STATE] = combineDiff(oldTypedState[DynamicState.SESSION_STATE], typedState[DynamicState.SESSION_STATE]);
							}
						}
					}
					// change baseDiff back from names to typed states
					for (i = 0; i < baseDiff.length; i++)
						baseDiff[i] = baseLookup[baseDiff[i]];
				}
				else // not typed session state
				{
					// overwrite old Array with new Array's values
					i = baseDiff.length = diffToAdd.length;
					while (i--)
					{
						var value:Object = diffToAdd[i];
						if (value === null || typeof value != 'object')
							baseDiff[i] = value; // avoid function call overhead
						else
							baseDiff[i] = combineDiff(baseDiff[i], value);
					}
				}
			}
			else // nested object
			{
				for (var newName:String in diffToAdd)
					baseDiff[newName] = combineDiff(baseDiff[newName], diffToAdd[newName]);
			}
			
			return baseDiff;
		}
		
		public function testDiff():void
		{
			var states:Array = [
				[
					{objectName: 'a', className: 'aClass', sessionState: 'aVal'},
					{objectName: 'b', className: 'bClass', sessionState: 'bVal1'}
				],
				[
					{objectName: 'b', className: 'bClass', sessionState: 'bVal2'},
					{objectName: 'a', className: 'aClass', sessionState: 'aVal'}
				],
				[
					{objectName: 'a', className: 'aNewClass', sessionState: 'aVal'},
					{objectName: 'b', className: 'bClass', sessionState: null}
				],
				[
					{objectName: 'b', className: 'bClass', sessionState: null}
				]
			];
			var diffs:Array = [];
			var combined:Array = [];
			var baseDiff:* = null;
			for (var i:int = 1; i < states.length; i++)
			{
				var diff:* = computeDiff(states[i - 1], states[i]);
				diffs.push(diff);
				baseDiff = combineDiff(baseDiff, diff);
				combined.push(ObjectUtil.copy(baseDiff));
			}
			trace('diffs',ObjectUtil.toString(diffs));
			trace('combined',ObjectUtil.toString(combined));
		}
	}
}
