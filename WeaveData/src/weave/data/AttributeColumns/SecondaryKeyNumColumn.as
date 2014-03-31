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

package weave.data.AttributeColumns
{
	import flash.utils.Dictionary;
	import flash.utils.getQualifiedClassName;
	
	import mx.formatters.NumberFormatter;
	import mx.utils.ObjectUtil;
	
	import weave.api.WeaveAPI;
	import weave.api.data.ColumnMetadata;
	import weave.api.data.DataTypes;
	import weave.api.data.IPrimitiveColumn;
	import weave.api.data.IQualifiedKey;
	import weave.api.newLinkableChild;
	import weave.api.registerLinkableChild;
	import weave.api.reportError;
	import weave.compiler.StandardLib;
	import weave.core.LinkableBoolean;
	import weave.core.LinkableString;
	import weave.utils.AsyncSort;
	import weave.utils.EquationColumnLib;
	
	public class SecondaryKeyNumColumn extends AbstractAttributeColumn implements IPrimitiveColumn
	{
		public function SecondaryKeyNumColumn(metadata:Object = null)
		{
			super(metadata);
			secondaryKeyFilter.addImmediateCallback(this, triggerCallbacks);
			useGlobalMinMaxValues.addImmediateCallback(this, triggerCallbacks);
		}

		/**
		 * This overrides the base title value
		 */
		public var baseTitle:String;

		/**
		 * This function overrides the min,max values.
		 */
		override public function getMetadata(propertyName:String):String
		{
			if (useGlobalMinMaxValues.value)
			{
				if (propertyName == ColumnMetadata.MIN)
					return String(_minNumber);
				if (propertyName == ColumnMetadata.MAX)
					return String(_maxNumber);
			}
			
			var value:String = super.getMetadata(propertyName);
			
			switch (propertyName)
			{
				case ColumnMetadata.TITLE:
					value = baseTitle || value;
					if (value != null && secondaryKeyFilter.value && !allKeysHack)
						return value + ' (' + secondaryKeyFilter.value + ')';
					break;
				case ColumnMetadata.KEY_TYPE:
					if (secondaryKeyFilter.value == null)
						return value + TYPE_SUFFIX
					break;
				case ColumnMetadata.DATA_TYPE:
					return _dataType == String ? DataTypes.STRING : DataTypes.NUMBER;
			}
			
			return value;
		}
		
		private var TYPE_SUFFIX:String = ',Year';
		
		private var _minNumber:Number = NaN; // returned by getMetadata
		private var _maxNumber:Number = NaN; // returned by getMetadata
		
		/**
		 * This object maps keys to data values.
		 */
		protected var _keyToNumericDataMapping:Dictionary = new Dictionary();
		protected var _keyToNumericDataMappingAB:Dictionary = new Dictionary();

		/**
		 * Derived from the record data, this is a list of all existing values in the dimension, each appearing once, sorted alphabetically.
		 */
		private const _uniqueStrings:Vector.<String> = new Vector.<String>();

		/**
		 * This is the value used to filter the data.
		 */
		public static const secondaryKeyFilter:LinkableString = new LinkableString();
		public static const useGlobalMinMaxValues:LinkableBoolean = new LinkableBoolean(true);
		
		protected const _uniqueSecondaryKeys:Array = new Array();
		public function get secondaryKeys():Array
		{
			return _uniqueSecondaryKeys;
		}

		/**
		 * This is a list of unique keys this column defines values for.
		 */
		protected const _uniqueKeysA:Array = new Array();
		protected const _uniqueKeysAB:Array = new Array();
		override public function get keys():Array
		{
			if (secondaryKeyFilter.value == null || allKeysHack) // when no secondary key specified, use the real unique keys
				return _uniqueKeysAB;
			return _uniqueKeysA;
		}
		
		public static var allKeysHack:Boolean = false; // used by DataTableTool
		
		/**
		 * @param key A key to test.
		 * @return true if the key exists in this IKeySet.
		 */
		override public function containsKey(key:IQualifiedKey):Boolean
		{
			var skfv:String = secondaryKeyFilter.value;
			if (skfv == null || allKeysHack)
				return _keyToNumericDataMappingAB[key] !== undefined;
			
			var d:Dictionary = _keyToNumericDataMapping[key] as Dictionary;
			return d && d[skfv] !== undefined;
		}

		public function updateRecords(keysA:Vector.<IQualifiedKey>, keysB:Vector.<String>, data:Array):void
		{
			if (_uniqueStrings.length > 0)
			{
				reportError("Replacing existing records is not supported");
			}
			
			var index:int, qkeyA:IQualifiedKey, keyB:String, qkeyAB:IQualifiedKey;
			var _key:*;
			var dataObject:* = null;

			if (keysA.length != data.length || keysB.length != data.length)
			{
				reportError("Array lengths differ");
				return;
			}
			
			// clear previous data mapping
			_keyToNumericDataMapping = new Dictionary();
			
			//if it's string data - create list of unique strings
			var dataType:String = getMetadata(ColumnMetadata.DATA_TYPE);
			if (data[0] is String || (dataType && dataType != DataTypes.NUMBER))
			{
				if (!dataType)
					dataType = DataTypes.STRING;
				for (var i:int = 0; i < data.length; i++)
				{
					if (_uniqueStrings.indexOf(data[i]) < 0)
						_uniqueStrings.push(data[i]);
				}
				AsyncSort.sortImmediately(_uniqueStrings, AsyncSort.compareCaseInsensitive);
				
				// min,max numbers are the min,max indices in the unique strings array
				_minNumber = 0;
				_maxNumber = _uniqueStrings.length - 1; 
			}
			else
			{
				dataType = DataTypes.NUMBER;
				// reset min,max before looping over records
				_minNumber = NaN;
				_maxNumber = NaN;
			}
			_metadata[ColumnMetadata.DATA_TYPE] = dataType;
			_dataType = dataType == DataTypes.STRING ? String : Number;
			
			// save a mapping from keys to data
			for (index = 0; index < keysA.length; index++)
			{
				qkeyA = keysA[index] as IQualifiedKey;
				keyB = keysB[index] as String;
				dataObject = data[index];
				
				qkeyAB = WeaveAPI.QKeyManager.getQKey(qkeyA.keyType + TYPE_SUFFIX, qkeyA.localName + ',' + keyB);
				//if we don't already have keyB - add it to _uniqueKeysB
				//  @todo - optimize this - searching every time is not the optimal method
				if (_uniqueSecondaryKeys.indexOf(keyB) < 0)
					_uniqueSecondaryKeys.push(keyB);
				if (! _keyToNumericDataMapping[qkeyA])
					_keyToNumericDataMapping[qkeyA] = new Dictionary();
				if (dataObject is String)
				{
					var iString:int = _uniqueStrings.indexOf(dataObject as String);
					if (iString < 0)
					{
						//iString = _uniqueStrings.push(dataObject as String) - 1;
						iString = _uniqueStrings.length;
						_uniqueStrings[iString] = dataObject as String;
					}
					_keyToNumericDataMapping[qkeyA][keyB] = iString;
					_keyToNumericDataMappingAB[qkeyAB] = iString;
				}
				else
				{
					_keyToNumericDataMapping[qkeyA][keyB] = dataObject;//Number(dataObject);
					_keyToNumericDataMappingAB[qkeyAB] = dataObject;//Number(dataObject);
					
					_minNumber = isNaN(_minNumber) ? dataObject : Math.min(_minNumber, dataObject);
					_maxNumber = isNaN(_maxNumber) ? dataObject : Math.max(_maxNumber, dataObject);
				}
			}
			
			AsyncSort.sortImmediately(_uniqueSecondaryKeys);
			
			// save list of unique keys
			index = 0;
			for (_key in _keyToNumericDataMapping)
				_uniqueKeysA[index++] = _key;
			_uniqueKeysA.length = index; // trim to new size
			
			index = 0;
			for (_key in _keyToNumericDataMappingAB)
				_uniqueKeysAB[index++] = _key;
			_uniqueKeysAB.length = index; // trim to new size
			
			triggerCallbacks();
		}

		/**
		 * the NumberFormatter to use when generating a string from a number
		 */
		private var _numberFormatter:NumberFormatter = new NumberFormatter();

		/**
		 * maximum number of significant digits to return when calling deriveStringFromNorm()
		 */		
		private var maxDerivedSignificantDigits:uint = 10;
		
		// get a string value for a given numeric value
		public function deriveStringFromNumber(number:Number):String
		{
			if (int(number) == number && (_uniqueStrings.length > 0) && (number < _uniqueStrings.length))
				return _uniqueStrings[number];
			
			if (_numberFormatter == null)
				return number.toString();
			else
				return _numberFormatter.format(
					StandardLib.roundSignificant(
							number,
							maxDerivedSignificantDigits
						)
					);
		}
		
		private var _qkeyCache:Dictionary = new Dictionary(true);
		private var _dataType:Class;

		/**
		 * get data from key value
		 */
		override public function getValueFromKey(qkey:IQualifiedKey, dataType:Class = null):*
		{
			if (!dataType)
				dataType = _dataType;
			
			var value:Number = NaN;
			if (_keyToNumericDataMappingAB[qkey] !== undefined)
				value = _keyToNumericDataMappingAB[qkey];
			else if (_keyToNumericDataMapping[qkey] !== undefined)
				value = _keyToNumericDataMapping[qkey][secondaryKeyFilter.value];
			
			if (isNaN(value))
				return EquationColumnLib.cast(undefined, dataType);
			
			if (dataType == IQualifiedKey)
			{
				if (_qkeyCache[qkey] === undefined)
				{
					var type:String = getMetadata(ColumnMetadata.DATA_TYPE);
					if (type == DataTypes.NUMBER)
						return null;
					if (type == '')
						type = DataTypes.STRING;
					_qkeyCache[qkey] = WeaveAPI.QKeyManager.getQKey(type, deriveStringFromNumber(value));
				}
				return _qkeyCache[qkey];
			}
			
			if (dataType == String)
				return deriveStringFromNumber(value);
			
			return value;
		}

		override public function toString():String
		{
			return debugId(this) + '{recordCount: '+keys.length+', keyType: "'+getMetadata('keyType')+'", title: "'+getMetadata('title')+'"}';
		}

	}
}
