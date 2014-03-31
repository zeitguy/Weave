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

package weave.utils
{
	import flash.geom.Point;
	import flash.utils.Dictionary;
	
	import weave.api.WeaveAPI;
	import weave.api.core.ILinkableVariable;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IKeySet;
	import weave.api.data.IQualifiedKey;
	import weave.compiler.StandardLib;
	import weave.core.ClassUtils;
	import weave.data.AttributeColumns.DynamicColumn;
	import weave.data.StatisticsCache;
	
	/**
	 * This class contains static functions that access values from IAttributeColumn objects.
	 * Many of the functions in this library use the static variable 'currentRecordKey'.
	 * This value should be set before calling a function that uses it.
	 * 
	 * @author adufilie
	 */
	public class EquationColumnLib
	{
		public static var debug:Boolean = false;
		
		/**
		 * This value should be set before calling any of the functions below that get values from IAttributeColumns.
		 */
		public static var currentRecordKey:IQualifiedKey = null;
		
		/**
		 * This function calls column.getValueFromKey(currentRecordKey, IQualifiedKey)
		 * @param column A column, or null if you want the currentRecordKey to be returned.
		 * @return The value at the current record in the column cast as an IQualifiedKey.
		 */
		public static function getKey(column:IAttributeColumn = null):IQualifiedKey
		{
			if (column)
				return column.getValueFromKey(currentRecordKey, IQualifiedKey);
			return currentRecordKey;
		}
		
		/**
		 * This function uses currentRecordKey when retrieving a value from a column.
		 * @param object An IAttributeColumn or an ILinkableVariable to get a value from.
		 * @param dataType Either a Class object or a String containing the qualified class name of the desired value type.
		 * @return The value of the object, optionally cast to the requested dataType.
		 */
		public static function getValue(object:Object, dataType:* = null):*
		{
			// remember current key
			var key:IQualifiedKey = currentRecordKey;

			if (dataType is String)
				dataType = ClassUtils.getClassDefinition(dataType);
			
			var value:* = null; // the value that will be returned
			
			// get the value from the object
			var column:IAttributeColumn = object as IAttributeColumn;
			if (column != null)
			{
				value = column.getValueFromKey(key, dataType as Class);
			}
			else if (object is ILinkableVariable)
			{
				value = (object as ILinkableVariable).getSessionState();
				// cast the value to the requested type
				if (dataType != null)
					value = cast(value, dataType);
			}
			else if (dataType != null)
			{
				value = cast(value, dataType);
			}
			
			// revert to key that was set when entering the function (in case nested calls modified the static variables)
			currentRecordKey = key;
			if (debug)
				debugTrace('getValue',object,key.localName,String(value));
			return value;
		}
		/**
		 * This function calls IAttributeColumn.getValueFromKey(key, dataType).
		 * @param column An IAttributeColumn to get a value from.
		 * @param key A key to get the value for.
		 * @return The result of calling column.getValueFromKey(key, dataType).
		 */
		public static function getValueFromKey(column:IAttributeColumn, key:IQualifiedKey, dataType:* = null):*
		{
			// remember current key
			var previousKey:IQualifiedKey = currentRecordKey;
			
			currentRecordKey = key;
			var value:* = getValue(column, dataType);
			
			// revert to key that was set when entering the function
			currentRecordKey = previousKey;

			if (debug)
				debugTrace('getValueFromKey',column,key.localName,String(value));
			return value;
		}
		
		/**
		 * This function gets a value from a data column, using a filter column and a key column to filter the data
		 * @param keyColumn An IAttributeColumn to get keys from
		 * @param filter column to use to filter data (ex: year)
		 * @param data An IAttributeColumn to get a value from
		 * @param filterValue value in filtercolumn to use to filter data
		 * @param filterDataType Class object of the desired filter value type
		 * @param dataType Class object of the desired value type 
		 * @return the correct filtered value from the data column
		 * @author kmanohar
		 */		
		public static function getValueFromFilterColumn(keyColumn:DynamicColumn, filter:IAttributeColumn, data:IAttributeColumn, filterValue:String, dataType:* = null):Object
		{
			var key:IQualifiedKey = getKey();
			var cubekeys:Array = getAssociatedKeys(keyColumn, key);
			
			for each (var cubekey:IQualifiedKey in cubekeys)
			{
				if (filter.getValueFromKey(cubekey, String) == filterValue)
				{
					var val:Object = getValueFromKey(data, cubekey, dataType);
					return val;
				}
			}
			return cast(NaN, dataType);
		}
		
		private static var _reverseKeyLookupTriggerCounter:Dictionary = new Dictionary(true);
		private static var _reverseKeyLookupCache:Dictionary = new Dictionary(true);
		
		/**
		 * This function returns a list of IQualifiedKey objects using a reverse lookup of value-key pairs 
		 * @param column An attribute column
		 * @param keyValue The value to look up
		 * @return An array of record keys with the given value under the given column
		 */
		public static function getAssociatedKeys(column:IAttributeColumn, keyValue:IQualifiedKey):Array
		{
			var lookup:Dictionary = _reverseKeyLookupCache[column] as Dictionary;
			if (lookup == null || column.triggerCounter != _reverseKeyLookupTriggerCounter[column]) // if cache is invalid, validate it now
			{
				_reverseKeyLookupTriggerCounter[column] = column.triggerCounter;
				_reverseKeyLookupCache[column] = lookup = new Dictionary(true);
				for each (var recordKey:IQualifiedKey in column.keys)
				{
					var value:IQualifiedKey = column.getValueFromKey(recordKey, IQualifiedKey) as IQualifiedKey;
					if (value == null)
						continue;
					var keys:Array = lookup[value] as Array;
					if (keys == null)
						lookup[value] = keys = [];
					keys.push(recordKey);
				}
			}
			return lookup[keyValue] as Array;
		}
		
		/**
		 * This function uses currentRecordKey when retrieving a value from a column if no key is specified.
		 * @param object An IAttributeColumn or an ILinkableVariable to get a value from.
		 * @param key A key to get the Number for.
		 * @return The value of the object, cast to a Number.
		 */
		public static function getNumber(object:Object, key:IQualifiedKey = null):Number
		{
			// remember current key
			var previousKey:IQualifiedKey = currentRecordKey;
			
			if (key == null)
				key = currentRecordKey;
			
			var result:Number;
			var column:IAttributeColumn = object as IAttributeColumn;
			if (column != null)
			{
				result = (object as IAttributeColumn).getValueFromKey(key, Number);
			}
			else if (object is ILinkableVariable)
			{
				result = StandardLib.asNumber((object as ILinkableVariable).getSessionState());
			}
			else
				throw new Error('first parameter must be either an IAttributeColumn or an ILinkableVariable');
			
			// revert to key that was set when entering the function (in case nested calls modified the static variables)
			currentRecordKey = previousKey;
			if (debug)
				debugTrace('getNumber',column,key.localName,String(result));
			return result;
		}
		/**
		 * This function uses currentRecordKey when retrieving a value from a column if no key is specified.
		 * @param object An IAttributeColumn or an ILinkableVariable to get a value from.
		 * @param key A key to get the Number for.
		 * @return The value of the object, cast to a String.
		 */
		public static function getString(object:Object, key:IQualifiedKey = null):String
		{
			// remember current key
			var previousKey:IQualifiedKey = currentRecordKey;
			
			if (key == null)
				key = currentRecordKey;

			var result:String = '';
			var column:IAttributeColumn = object as IAttributeColumn;
			if (column != null)
			{
				result = (object as IAttributeColumn).getValueFromKey(key, String);
			}
			else if (object is ILinkableVariable)
			{
				result = StandardLib.asString((object as ILinkableVariable).getSessionState());
			}
			else
				throw new Error('first parameter must be either an IAttributeColumn or an ILinkableVariable');

			// revert to key that was set when entering the function (in case nested calls modified the static variables)
			currentRecordKey = previousKey;
			if (debug)
				debugTrace('getString',column,key.localName,String(result));
			return result;
		}
		/**
		 * This function uses currentRecordKey when retrieving a value from a column if no key is specified.
		 * @param object An IAttributeColumn or an ILinkableVariable to get a value from.
		 * @param key A key to get the Number for.
		 * @return The value of the object, cast to a Boolean.
		 */
		public static function getBoolean(object:Object, key:IQualifiedKey = null):Boolean
		{
			// remember current key
			var previousKey:IQualifiedKey = currentRecordKey;
			
			if (key == null)
				key = currentRecordKey;

			var result:Boolean = false;
			var column:IAttributeColumn = object as IAttributeColumn;
			if (column != null)
			{
				result = column.getValueFromKey(key, Boolean);
			}
			else if (object is ILinkableVariable)
			{
				result = StandardLib.asBoolean((object as ILinkableVariable).getSessionState());
			}
			else
				throw new Error('first parameter must be either an IAttributeColumn or an ILinkableVariable');

			// revert to key that was set when entering the function (in case nested calls modified the static variables)
			currentRecordKey = previousKey;
			if (debug)
				debugTrace('getBoolean',column,key.localName,String(result));
			return result;
		}
		/**
		 * This function uses currentRecordKey when retrieving a value from a column if no key is specified.
		 * @param column A column to get a value from.
		 * @param key A key to get the Number for.
		 * @return The Number corresponding to the given key, normalized to be between 0 and 1.
		 */
		[Deprecated(replacement="WeaveAPI.StatisticsCache.getColumnStatistics(column).getNorm(key)")]
		public static function getNorm(column:IAttributeColumn, key:IQualifiedKey = null):Number
		{
			// remember current key
			var previousKey:IQualifiedKey = currentRecordKey;
			
			if (key == null)
				key = currentRecordKey;

			var result:Number = NaN;
			if (column != null)
				result = WeaveAPI.StatisticsCache.getColumnStatistics(column).getNorm(key);
			else
				throw new Error('first parameter must be an IAttributeColumn');

			// revert to key that was set when entering the function (in case nested calls modified the static variables)
			currentRecordKey = previousKey;
			if (debug)
				debugTrace('getNorm',column,key.localName,String(result));
			return result;
		}
		
		/**
		 * This will check a list of IKeySets for an IQualifiedKey.
		 * @param keySets A list of IKeySets (can be IAttributeColumns).
		 * @param key A key to search for.
		 * @return The first IKeySet that contains the key.
		 */
		public static function findKeySet(keySets:Array, key:IQualifiedKey = null):IKeySet
		{
			// remember current key
			var previousKey:IQualifiedKey = currentRecordKey;
			
			if (key == null)
				key = currentRecordKey;
			
			var keySet:IKeySet = null;
			for (var i:int = 0; i < keySets.length; i++)
			{
				keySet = keySets[i] as IKeySet;
				if (keySet && keySet.containsKey(key))
					break;
				else
					keySet = null;
			}
			
			// revert to key that was set when entering the function (in case nested calls modified the static variables)
			currentRecordKey = previousKey;
			return keySet;
		}
		
		[Deprecated] public static function getSum(column:IAttributeColumn):Number
		{
			return WeaveAPI.StatisticsCache.getColumnStatistics(column).getSum();
		}
		
		[Deprecated] public static function getMean(column:IAttributeColumn):Number
		{
			return WeaveAPI.StatisticsCache.getColumnStatistics(column).getMean();
		}
		
		[Deprecated] public static function getVariance(column:IAttributeColumn):Number
		{
			return WeaveAPI.StatisticsCache.getColumnStatistics(column).getVariance();
		}
		
		[Deprecated] public static function getStandardDeviation(column:IAttributeColumn):Number
		{
			return WeaveAPI.StatisticsCache.getColumnStatistics(column).getStandardDeviation();
		}
		
		[Deprecated] public static function getMin(column:IAttributeColumn):Number
		{
			return WeaveAPI.StatisticsCache.getColumnStatistics(column).getMin();
		}
		
		[Deprecated] public static function getMax(column:IAttributeColumn):Number
		{
			return WeaveAPI.StatisticsCache.getColumnStatistics(column).getMax();
		}
		
		[Deprecated] public static function getCount(column:IAttributeColumn):Number
		{
			return WeaveAPI.StatisticsCache.getColumnStatistics(column).getCount();
		}
		
		[Deprecated] public static function getRunningTotal(column:IAttributeColumn, key:IQualifiedKey = null):Number
		{
			// remember current key
			var previousKey:IQualifiedKey = currentRecordKey;
			
			if (key == null)
				key = currentRecordKey;

			var result:Number = NaN;
			if (column != null)
			{
				var runningTotals:Dictionary = (WeaveAPI.StatisticsCache as StatisticsCache).getRunningTotals(column);
				if (runningTotals != null)
					result = runningTotals[key];
			}

			// revert to key that was set when entering the function (in case nested calls modified the static variables)
			currentRecordKey = previousKey;
			return result;
		}
		/**
		 * @param value A value to cast.
		 * @param newType Either a qualifiedClassName or a Class object referring to the type to cast the value as.
		 */
		public static function cast(value:*, newType:*):*
		{
			if (newType == null)
				return value;
			
			// if newType is a qualified class name, get the Class definition
			if (newType is String)
				newType = ClassUtils.getClassDefinition(newType);

			// cast the value as the desired type
			if (newType == Number)
			{
				value = StandardLib.asNumber(value);
			}
			else if (newType == String)
			{
				value = StandardLib.asString(value);
			}
			else if (newType == Boolean)
			{
				value = StandardLib.asBoolean(value);
			}
			else if (newType == int)
			{
				value = StandardLib.asNumber(value);
				if (isNaN(value))
					return NaN;
				return int(value);
			}

			return value as newType;
		}
		
		/**
		 * This function transforms an x,y coordinate pair from one coordinate reference system to another.
		 * @param sourceSRS Specifies the source coordinate reference system.
		 * @param destinationSRS Specifies the destination coordinate reference system.
		 * @param x The X coordinate in the coordinate reference system specified by sourceSRS.
		 * @param y The Y coordinate in the coordinate reference system specified by sourceSRS.
		 * @return A new Point object containing the transformed coordinates.
		 */		
		public static function transformCoords(sourceSRS:String, destinationSRS:String, x:Number, y:Number):Point
		{
			var _tempPoint:Point = new Point();
			_tempPoint.x = x;
			_tempPoint.y = y;
			return WeaveAPI.ProjectionManager.transformPoint(sourceSRS, destinationSRS, _tempPoint);
		}
		
		/**
		 * This is a macro for IQualifiedKey that can be used in equations.
		 */		
		public static const QKey:Class = IQualifiedKey;
	}
}
