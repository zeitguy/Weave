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
	import flash.utils.Dictionary;
	
	import mx.collections.ArrayCollection;
	import mx.collections.ICollectionView;
	import mx.collections.IViewCursor;
	
	/**
	 * This class contains static functions that manipulate Vectors and Arrays.
	 * Functions with * as parameter types support both Vector and Array.
	 * Vector.&lt;*&rt; is not used because it causes compiler errors.
	 * 
	 * @author adufilie
	 */
	public class VectorUtils
	{
		private static var _lookup:Dictionary = new Dictionary(true);
		private static var _lookupId:int = 0;
		
		/**
		 * Computes the union of the items in a list of Arrays. Can also be used to get a list of unique items in an Array.
		 * @param arrays A list of Arrays.
		 * @return The union of all the unique items in the Arrays in the order they appear.
		 */
		public static function union(...arrays):Array
		{
			var result:Array = [];
			_lookupId++;
			for each (var array:* in arrays)
			{
				for each (var item:* in array)
				{
					if (_lookup[item] !== _lookupId)
					{
						_lookup[item] = _lookupId;
						result.push(item);
					}
				}
			}
			return result;
		}
		
		
		/**
		 * Computes the intersection of the items in a list of two or more Arrays.
		 * @param arrays A list of Arrays.
		 * @return The intersection of the items appearing in all Arrays, in the order that they appear in the first Array.
		 */
		public static function intersection(firstArray:*, secondArray:*, ...moreArrays):Array
		{
			moreArrays.unshift(secondArray);
			
			var result:Array = [];
			var item:*;
			var lastArray:* = moreArrays.pop();
			
			_lookupId++;
			for each (item in lastArray)
				_lookup[item] = _lookupId;
			
			for each (var array:* in moreArrays)
			{
				for each (item in array)
					if (_lookup[item] === _lookupId)
						_lookup[item] = _lookupId + 1;
				_lookupId++;
			}
			
			for each (item in firstArray)
				if (_lookup[item] === _lookupId)
					result.push(item);
			
			return result;
		}
		
		/**
		 * This function copies the contents of the source to the destination.
		 * Either parameter may be either an Array or a Vector.
		 * @param source An Array-like object.
		 * @param destination An Array or Vector.
		 * @return A pointer to the destination Array (or Vector)
		 */
		public static function copy(source:*, destination:* = null):*
		{
			if (!destination)
				destination = [];
			destination.length = source.length;
			for (var i:* in source)
				destination[i] = source[i];
			return destination;
		}
		/**
		 * Fills a hash map with the keys from an Array.
		 */
		public static function fillKeys(output:Object, keys:Array):void
		{
			for each (var key:* in keys)
				output[key] = true;
		}
		/**
		 * Gets all keys in a hash map.
		 */
		public static function getKeys(hashMap:Object):Array
		{
			var keys:Array = [];
			for (var key:* in hashMap)
				keys.push(key);
			return keys;
		}
		
		/**
		 * Efficiently removes duplicate adjacent items in a pre-sorted Array (or Vector).
		 * @param vector The sorted Array (or Vector)
		 */
		public static function removeDuplicatesFromSortedArray(vector:*):void
		{
			var iEnd:int = vector.length;
			var iPrevWrite:int = 0; // always keep first item 
			var iRead:int = 1; // start by reading second item
			for (; iRead < iEnd; iRead++) // increment iRead unconditionally
			{
				// only copy current item if it is different from the previous
				if (vector[iPrevWrite] != vector[iRead])
					vector[++iPrevWrite] = vector[iRead];
			}
			if (iEnd > 0)
				vector.length = iPrevWrite + 1;
		}
		/**
		 * randomizes the order of the elements in the vector in O(n) time by modifying the given array.
		 * @param the vector to randomize
		 */
		public static function randomSort(vector:*):void
		{
			var length:int = vector.length;
			for (var i:int = length; i--;)
			{
				// randomly choose index j
				var j:int = Math.floor(Math.random() * length);
				// swap elements i and j
				var temp:* = vector[i];
				vector[i] = vector[j];
				vector[j] = temp;
			}
		}
		
		/**
		 * See http://en.wikipedia.org/wiki/Quick_select#Partition-based_general_selection_algorithm
		 * @param list An Array or Vector to be re-organized
		 * @param firstIndex The index of the first element in the list to partition.
		 * @param lastIndex The index of the last element in the list to partition.
		 * @param pivotIndex The index of an element to use as a pivot when partitioning.
		 * @param compareFunction A function that takes two array elements a,b and returns -1 if a&lt;b, 1 if a&gt;b, or 0 if a==b.
		 * @return The index the pivot element was moved to during the execution of the function.
		 */
		private static function partition(list:*, firstIndex:int, lastIndex:int, pivotIndex:int, compareFunction:Function):int
		{
			var temp:*;
			var pivotValue:* = list[pivotIndex];
			// Move pivot to end
			temp = list[pivotIndex];
			list[pivotIndex] = list[lastIndex];
			list[lastIndex] = temp;
			
			var storeIndex:int = firstIndex;
			for (var i:int = firstIndex; i < lastIndex; i++)
			{
				if (compareFunction(list[i], pivotValue) < 0)
				{
					if (storeIndex != i)
					{
						// swap elements at storeIndex and i
						temp = list[storeIndex];
						list[storeIndex] = list[i];
						list[i] = temp;
					}
					
					storeIndex++;
				}
			}
			if (storeIndex != lastIndex)
			{
				// Move pivot to its final place
				temp = list[storeIndex];
				list[storeIndex] = list[lastIndex];
				list[lastIndex] = temp;
			}
			// everything to the left of storeIndex is < pivot element
			// everything to the right of storeIndex is >= pivot element
			return storeIndex;
		}
		
		//testPartition()
		private static function testPartition():void
		{
			var list:Array = [3,7,5,8,2];
			var pivotIndex:int = partition(list, 0, list.length - 1, list.length/2, AsyncSort.defaultCompare);
			
			for (var i:int = 0; i < list.length; i++)
				if (i < pivotIndex != list[i] < list[pivotIndex])
					throw new Error('assertion fail');
		}
		
		/**
		 * See http://en.wikipedia.org/wiki/Quick_select#Partition-based_general_selection_algorithm
		 * @param list An Array or Vector to be re-organized.
		 * @param compareFunction A function that takes two array elements a,b and returns -1 if a&lt;b, 1 if a&gt;b, or 0 if a==b.
		 * @param firstIndex The index of the first element in the list to calculate a median from.
		 * @param lastIndex The index of the last element in the list to calculate a median from.
		 * @return The index the median element.
		 */
		public static function getMedianIndex(list:*, compareFunction:Function, firstIndex:int = 0, lastIndex:int = -1):int
		{
			var left:int = firstIndex;
			var right:int = (lastIndex >= 0) ? (lastIndex) : (list.length - 1);
			if (left >= right)
				return left;
			var medianIndex:int = (left + right) / 2;
			while (true)
			{
				var pivotIndex:int = partition(list, left, right, (left + right) / 2, compareFunction);
				if (medianIndex == pivotIndex)
					return medianIndex;
				if (medianIndex < pivotIndex)
					right = pivotIndex - 1;
				else
					left = pivotIndex + 1;
			}
			return -1;
		}

		/**
		 * Merges two previously-sorted arrays or vectors.
		 * @param sortedInputA The first sorted array or vector.
		 * @param sortedInputB The second sorted array or vector.
		 * @param mergedOutput A vector or array to store the merged arrays or vectors.
		 * @param comparator A function that takes two parameters and returns -1 if the first parameter is less than the second, 0 if equal, or 1 if the first is greater than the second.
		 */		
		public static function mergeSorted(sortedInputA:*, sortedInputB:*, mergedOutput:*, comparator:Function):void
		{
			var indexA:int = 0;
			var indexB:int = 0;
			var indexOut:int = 0;
			var lengthA:int = sortedInputA.length;
			var lengthB:int = sortedInputB.length;
			while (indexA < lengthA && indexB < lengthB)
				if (comparator(sortedInputA[indexA], sortedInputB[indexB]) < 0)
					mergedOutput[indexOut++] = sortedInputA[indexA++];
				else
					mergedOutput[indexOut++] = sortedInputB[indexB++];
			
			while (indexA < lengthA)
				mergedOutput[indexOut++] = sortedInputA[indexA++];
			
			while (indexB < lengthB)
				mergedOutput[indexOut++] = sortedInputB[indexB++];

			mergedOutput.length = indexOut;
		}

		/**
		 * This will flatten an Array of Arrays into a flat Array.
		 * Items will be appended to the destination Array.
		 * @param source A multi-dimensional Array to flatten.
		 * @param destination An Array or Vector to append items to.  If none specified, a new one will be created.
		 * @return The destination Array with all the nested items in the source appended to it.
		 */
		public static function flatten(source:Array, destination:* = null):*
		{
			if (destination == null)
				destination = [];
			if (source == null)
				return destination;

			for (var i:int = 0; i < source.length; i++)
				if (source[i] is Array || source[i] is Vector)
					flatten(source[i], destination);
				else
					destination.push(source[i]);
			return destination;
		}
		
		/**
		 * This will take an Array of Arrays of String items and produce a single list of String-joined items.
		 * @param arrayOfArrays An Array of Arrays of String items.
		 * @param separator The separator String used between joined items.
		 * @param includeEmptyItems Set this to true to include empty-strings and undefined items in the nested Arrays.
		 * @return An Array of String-joined items in the same order they appear in the nested Arrays.
		 */
		public static function joinItems(arrayOfArrays:Array, separator:String, includeEmptyItems:Boolean):Array
		{
			var maxLength:int = 0;
			var itemList:Array;
			for each (itemList in arrayOfArrays)
				maxLength = Math.max(maxLength, itemList.length);
			
			var result:Array = [];
			for (var itemIndex:int = 0; itemIndex < maxLength; itemIndex++)
			{
				var joinedItem:Array = [];
				for (var listIndex:int = 0; listIndex < arrayOfArrays.length; listIndex++)
				{
					itemList = arrayOfArrays[listIndex] as Array;
					var item:String = '';
					if (itemList && itemIndex < itemList.length)
						item = itemList[itemIndex] || '';
					if (item || includeEmptyItems)
						joinedItem.push(item);
				}
				result.push(joinedItem.join(separator));
			}
			return result;
		}
		
		/**
		 * Performs a binary search on a sorted array with no duplicate values.
		 * @param array Array or Vector of Numbers
		 * @param compare A compare function
		 * @param exactMatchOnly If true, searches for exact match. If false, searches for insertion point.
		 * @return The index of the matching value or insertion point.
		 */
		public static function binarySearch(array:*, item:*, exactMatchOnly:Boolean, compare:Function = null):int
		{
			var i:int = 0,
				imin:int = 0,
				imax:int = array.length - 1;
			while (imin <= imax)
			{
				i = (imin + imax) / 2;
				var a:* = array[i];
				var c:int = compare != null ? compare(item, a) : (item < a ? -1 : (item > a ? 1 : 0));
				if (c < 0)
					imax = i - 1;
				else if (c > 0)
					imin = ++i; // set i for possible insertion point
				else
					return i;
			}
			return exactMatchOnly ? -1 : i;
		}
		
		/**
		 * Gets an Array of items from an ICollectionView.
		 * @param collection The ICollectionView.
		 * @param alwaysMakeCopy If set to false and the collection is an ArrayCollection, returns original source Array.
		 */
		public static function getArrayFromCollection(collection:ICollectionView, alwaysMakeCopy:Boolean = true):Array
		{
			var array:Array = null;
			if (collection is ArrayCollection)
				array = (collection as ArrayCollection).source;
			if (array)
				return alwaysMakeCopy ? array.concat() : array;
			
			array = [];
			var cursor:IViewCursor = collection.createCursor();
			do
			{
				array.push(cursor.current);
			}
			while (cursor.moveNext());
			return array;
		}
		
		/**
		 * This will get a subset of properties/items/attributes from an Object/Array/XML.
		 * @param object An Object/Array/XML containing properties/items/attributes to retrieve.
		 * @param keys A list of property names, index values, or attribute names.
		 * @param output Optionally specifies where to store the resulting items.
		 * @return An Object (or Array) containing the properties/items/attributes specified by keysOrIndices.
		 */
		public static function getItems(object:*, keys:Array, output:* = null):*
		{
			if (!output)
				output = object is Array ? [] : {};
			for each (var key:* in keys)
			{
				if (object is XML_Class)
					output[key] = String((object as XML_Class).attribute(key));
				else
					output[key] = object[key];
			}
			return output;
		}
	}
}
