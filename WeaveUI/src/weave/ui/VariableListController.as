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
package weave.ui
{
	import mx.collections.ArrayCollection;
	import mx.collections.ICollectionView;
	import mx.controls.DataGrid;
	import mx.controls.dataGridClasses.DataGridColumn;
	import mx.controls.listClasses.ListBase;
	import mx.core.IUIComponent;
	import mx.core.mx_internal;
	import mx.events.DataGridEvent;
	import mx.events.DragEvent;
	import mx.events.ListEvent;
	import mx.managers.DragManager;
	
	import weave.api.core.ILinkableDynamicObject;
	import weave.api.core.ILinkableHashMap;
	import weave.api.core.ILinkableObject;
	import weave.api.data.IColumnReference;
	import weave.api.getCallbackCollection;
	import weave.api.newLinkableChild;
	import weave.core.LinkableWatcher;
	import weave.data.AttributeColumns.ReferencedColumn;
	
	/**
	 * Callbacks trigger when the list of objects changes.
	 */
	public class VariableListController implements ILinkableObject
	{
		public function VariableListController()
		{
		}
		
		public function dispose():void
		{
			view = null;
			hashMap = null;
			dynamicObject = null;
		}
		
		public function get view():ListBase
		{
			return _editor;
		}
		
		/**
		 * @param editor This can be either a List or a DataGrid.
		 */
		public function set view(editor:ListBase):void
		{
			if (_editor == editor)
				return;
			
			if (_editor)
			{
				_editor.removeEventListener(DragEvent.DRAG_OVER, dragOverHandler);
				_editor.removeEventListener(DragEvent.DRAG_DROP, dragDropHandler);
				_editor.removeEventListener(DragEvent.DRAG_COMPLETE, dragCompleteHandler);
				_editor.removeEventListener(DragEvent.DRAG_ENTER, dragEnterCaptureHandler, true);
				if (_editor is DataGrid)
					(_editor as DataGrid).removeEventListener(ListEvent.ITEM_EDIT_END, handleItemEditEnd);
			}
			
			_editor = editor;
			
			if (_editor)
			{
				_editor.dragEnabled = true;
				_editor.dropEnabled = true;
				_editor.dragMoveEnabled = true;
				_editor.allowMultipleSelection = _allowMultipleSelection;
				_editor.showDataTips = false;
				_editor.addEventListener(DragEvent.DRAG_OVER, dragOverHandler);
				_editor.addEventListener(DragEvent.DRAG_DROP, dragDropHandler);
				_editor.addEventListener(DragEvent.DRAG_COMPLETE, dragCompleteHandler);
				_editor.addEventListener(DragEvent.DRAG_ENTER, dragEnterCaptureHandler, true);
			}
			
			_nameColumn = null;
			_valueColumn = null;
			var dataGrid:DataGrid = _editor as DataGrid;
			if (dataGrid)
			{
				dataGrid.editable = true;
				dataGrid.addEventListener(ListEvent.ITEM_EDIT_END, handleItemEditEnd);
				dataGrid.draggableColumns = false;
				
				_nameColumn = new DataGridColumn();
				_nameColumn.sortable = false;
				_nameColumn.editable = true;
				_nameColumn.labelFunction = getObjectName;
				_nameColumn.showDataTips = true;
				_nameColumn.dataTipFunction = nameColumnDataTip;
				setNameColumnHeader();
				
				_valueColumn = new DataGridColumn();
				_valueColumn.sortable = false;
				_valueColumn.editable = false;
				_valueColumn.headerText = lang("Value");
				_valueColumn.labelFunction = getItemLabel;
				
				dataGrid.columns = [_nameColumn, _valueColumn];
			}
			else if (_editor)
			{
				_editor.labelFunction = getItemLabel;
			}
			
			if (dynamicObject && _editor)
				_editor.rowCount = 1;
			updateDataProvider();
		}
		
		private function setNameColumnHeader():void
		{
			if (!_nameColumn)
				return;
			if (hashMap && hashMap.getNames().length)
				_nameColumn.headerText = lang("Name (Click to edit)")
			else
				_nameColumn.headerText = lang("Name");
		}
		
		private function nameColumnDataTip(item:Object, ..._):String
		{
			return lang("{0} (Click to rename)", getObjectName(item));
		}
		
		private var _allowMultipleSelection:Boolean = true;
		
		public function set allowMultipleSelection(value:Boolean):void
		{
			_allowMultipleSelection = value;
			if (view)
				view.allowMultipleSelection = value;
		}
		
		private var _editor:ListBase;
		private var _nameColumn:DataGridColumn;
		private var _valueColumn:DataGridColumn;
		private const _hashMapWatcher:LinkableWatcher = newLinkableChild(this, LinkableWatcher, refreshLabels, true);
		private const _dynamicObjectWatcher:LinkableWatcher = newLinkableChild(this, LinkableWatcher, updateDataProvider, true);
		private const _childListWatcher:LinkableWatcher = newLinkableChild(this, LinkableWatcher, updateDataProvider);
		private var _labelFunction:Function = null;
		
		public function get hashMap():ILinkableHashMap
		{
			return _hashMapWatcher.target as ILinkableHashMap;
		}
		public function set hashMap(value:ILinkableHashMap):void
		{
			if (value)
				dynamicObject = null;
			
			_hashMapWatcher.target = value;
			_childListWatcher.target = value && value.childListCallbacks;
		}
		
		public function get dynamicObject():ILinkableDynamicObject
		{
			return _dynamicObjectWatcher.target as ILinkableDynamicObject;
		}
		public function set dynamicObject(value:ILinkableDynamicObject):void
		{
			if (value)
			{
				hashMap = null;
				if (_editor)
					_editor.rowCount = 1;
			}
			
			_dynamicObjectWatcher.target = value;
		}
		
		private function refreshLabels():void
		{
			if (_editor)
				_editor.labelFunction = _editor.labelFunction; // this refreshes the labels
		}
		
		private function updateDataProvider():void
		{
			if (!_editor)
				return;
			
			var vsp:int = _editor.verticalScrollPosition;
			var selectedItems:Array = _editor.selectedItems;
		
			if (dynamicObject)
			{
				_editor.dataProvider = dynamicObject.internalObject;
			}
			else if (hashMap)
			{
				setNameColumnHeader();
				_editor.dataProvider = hashMap.getObjects();
			}
			else
				_editor.dataProvider = null;
			
			if (!(_editor is DataGrid))
				_editor.rowCount = 1;
			
			var view:ICollectionView = _editor.dataProvider as ICollectionView;
			if (view)
				view.refresh();
			
			if (selectedItems && selectedItems.length)
			{
				_editor.validateProperties();
				if (vsp >= 0 && vsp <= _editor.maxVerticalScrollPosition)
					_editor.verticalScrollPosition = vsp;
				_editor.selectedItems = selectedItems;
			}
			
			getCallbackCollection(this).triggerCallbacks();
		}
		
		public function removeAllItems():void
		{
			if (hashMap)
				hashMap.removeAllObjects();
			else if (dynamicObject)
				dynamicObject.removeObject();
		}
		
		public function removeSelectedItems():void
		{
			if (hashMap && selectedIndex >= 0)
			{
				var names:Array = [];
				for (var i:int = 0; i < _editor.selectedIndices.length; i++)
				{
					var selectedIndex:int = _editor.selectedIndices[i];
					
					names.push(hashMap.getName(_editor.dataProvider[selectedIndex] as ILinkableObject) );
				}	
				
				for each(var name:String in names)
				{
					hashMap.removeObject(name);
				}
			}
			else if (dynamicObject)
			{
				dynamicObject.removeObject();
			}
		}
		
		public function beginEditVariableName(object:ILinkableObject):void
		{
			var dg:DataGrid = _editor as DataGrid;
			if (dg && hashMap)
			{
				var rowIndex:int = hashMap.getObjects().indexOf(object);
				if (rowIndex >= 0)
					dg.editedItemPosition = { columnIndex: 0, rowIndex: rowIndex };
			}
		}

		/**
		 * @param item
		 * @return The name of the item in the ILinkableHashMap or the ILinkableDynamicObject internal object's global name
		 */		
		public function getItemName(item:Object):String
		{
			if (hashMap)
				return hashMap.getName(item as ILinkableObject);
			if (dynamicObject)
				return dynamicObject.globalName;
			return null;
		}
		
		private function getItemLabel(item:Object, ..._):String
		{
			if (_labelFunction != null)
				return _labelFunction(item);
			else
				return getObjectName(item) || String(item);
		}
		
		public function set labelFunction(value:Function):void
		{
			_labelFunction = value;
			refreshLabels();
		}
		
		private function updateHashMapNameOrder():void
		{
			if (!_editor)
				return;
			
			_editor.validateNow();
			
			if (hashMap)
			{
				// update object map name order based on what is in the data provider
				var newNameOrder:Array = [];
				for (var i:int = 0; i < _editor.dataProvider.length; i++)
				{
					var object:ILinkableObject = _editor.dataProvider[i] as ILinkableObject;
					if (object)
						newNameOrder[i] = hashMap.getName(object);
				}
				hashMap.setNameOrder(newNameOrder);
			}
		}
		
		private function removeObjectsMissingFromDataProvider():void
		{
			if (!_editor)
				return;
			
			if (hashMap)
			{
				var objects:Array = hashMap.getObjects();
				for each (var object:ILinkableObject in objects)
				{
					if(!(_editor.dataProvider as ArrayCollection).contains(object))
						hashMap.removeObject(hashMap.getName(object));
				}
			}
			else if(dynamicObject)
			{
				if(!(_editor.dataProvider as ArrayCollection).contains(dynamicObject.internalObject))
					dynamicObject.removeObject();
			}
		}
		
		// called when something is being dragged on top of this list
		private function dragOverHandler(event:DragEvent):void
		{
			if (dragSourceIsAcceptable(event))
				DragManager.showFeedback(DragManager.MOVE);
			else
				DragManager.showFeedback(DragManager.NONE);
		}
		
		// called when something is dropped into this list
		private function dragDropHandler(event:DragEvent):void
		{
			//hides the drop visual lines
			event.currentTarget.hideDropFeedback(event);
			_editor.mx_internal::resetDragScrolling(); // if we don't do this, list will scroll when mouse moves even when not dragging something
			
			if (event.dragInitiator == _editor)
			{
				event.action = DragManager.MOVE;
				_editor.callLater(updateHashMapNameOrder);
			}
			else
			{
				event.preventDefault();
				
				var items:Array = event.dragSource.dataForFormat("items") as Array;
				if (hashMap)
				{
					var prevNames:Array = hashMap.getNames();
					var newNames:Array = [];
					var dropIndex:int = _editor.calculateDropIndex(event);
					var newObject:ILinkableObject;
					
					// copy items in reverse order because selectedItems is already reversed
					for (var i:int = items.length - 1; i >= 0; i--)
					{
						var object:ILinkableObject = items[i] as ILinkableObject;
						if (object && hashMap.getName(object) == null)
						{
							newObject = hashMap.requestObjectCopy(null, object);
							newNames.push(hashMap.getName(newObject));
						}
						
						var ref:IColumnReference = items[i] as IColumnReference;
						if (ref)
						{
							var meta:Object = ref.getColumnMetadata();
							if (meta)
							{
								var refCol:ReferencedColumn = hashMap.requestObject(null, ReferencedColumn, false);
								refCol.setColumnReference(ref.getDataSource(), meta);
								newObject = refCol;
								newNames.push(hashMap.getName(newObject));
							}
						}
					}
					
					// insert new names inside prev names list and save the new name order
					var args:Array = newNames;
					newNames.unshift(dropIndex, 0);
					prevNames.splice.apply(null, args);
					hashMap.setNameOrder(prevNames);
					
					if (items.length == 1 && newObject)
						beginEditVariableName(newObject);
				}
				else if (dynamicObject && items.length > 0)
				{
					// only copy the first item in the list
					dynamicObject.requestLocalObjectCopy(items[0]);
				}
			}
		}
		
		private function dragSourceIsAcceptable(event:DragEvent):Boolean
		{
			if (event.dragSource.hasFormat("items"))
			{
				var items:Array = event.dragSource.dataForFormat("items") as Array;
				for each (var item:Object in items)
				{
					var ref:IColumnReference = item as IColumnReference;
					if (item is ILinkableObject || (ref && ref.getColumnMetadata() != null))
						return true;
				}
			}
			return false;
		}
		
		// called when something is dragged on top of this list
		private function dragEnterCaptureHandler(event:DragEvent):void
		{
			if (dragSourceIsAcceptable(event))
				DragManager.acceptDragDrop(event.currentTarget as IUIComponent);
			event.preventDefault();
		}
		
		public var defaultDragAction:String = DragManager.COPY;
		
		// called when something in this list is dragged and dropped somewhere else
		private function dragCompleteHandler(event:DragEvent):void
		{
			if (event.shiftKey)
				event.action = DragManager.MOVE;
			else if (event.ctrlKey)
				event.action = DragManager.COPY;
			else
				event.action = defaultDragAction;
			
			_editor.callLater(removeObjectsMissingFromDataProvider);
		}
		
		private function getObjectName(item:Object, ..._):String
		{
			if (hashMap)
				return hashMap.getName(item as ILinkableObject);
			if (dynamicObject)
				return dynamicObject.globalName;
			return null;
		}
		
		protected function handleItemEditEnd(event:DataGridEvent):void
		{
			var oldName:String = hashMap.getName(event.itemRenderer.data as ILinkableObject);
			var grid:DataGrid = event.target as DataGrid;
			
			if (grid)
			{
				var col:int = event.columnIndex;
				var field:String = (grid.columns[col] as DataGridColumn).editorDataField;
				var newValue:String = grid.itemEditorInstance[field];
				
				if (hashMap && newValue && hashMap.getNames().indexOf(newValue) < 0)
					hashMap.renameObject(oldName, newValue);
				
				if (dynamicObject && newValue != dynamicObject.globalName)
					dynamicObject.globalName = newValue;
			}
		}
	}
}