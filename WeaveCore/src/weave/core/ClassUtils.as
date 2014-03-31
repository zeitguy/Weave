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
	import avmplus.getQualifiedClassName;
	
	import flash.system.ApplicationDomain;

	/**
	 * This is an all-static class containing functions related to qualified class names.
	 * 
	 * @author adufilie
	 */
	public class ClassUtils
	{
		/**
		 * This function gets a Class definition for a qualified class name.
		 * @param classQName The qualified name of a class.
		 * @return The class definition, or null if the class cannot be resolved.
		 */
		public static function getClassDefinition(classQName:String):Class
		{
			var domain:ApplicationDomain = ApplicationDomain.currentDomain;
			if (domain.hasDefinition(classQName))
				return domain.getDefinition(classQName) as Class;
			return _deprecatedLookup[classQName];
		}
		
		/**
		 * This tests if a class exists.
		 * @param classQName The qualified class name.
		 * @return true if the class exists.
		 */
		public static function hasClassDefinition(classQName:String):Boolean
		{
			var domain:ApplicationDomain = ApplicationDomain.currentDomain;
			if (domain.hasDefinition(classQName))
				return true;
			return !!_deprecatedLookup[classQName];
		}
		
		/**
		 * Checks if a class is deprecated.
		 * @param classQName The qualified class name.
		 * @return true if the class is deprecated.
		 */
		public static function isClassDeprecated(classQName:String):Boolean
		{
			return cacheClassInfo(classQName) && !!_deprecatedLookup[classQName];
		}
		
		/**
		 * Storage for registerDeprecatedClass()
		 * @see #registerDeprecatedClass()
		 */
		private static const _deprecatedLookup:Object = {};
		
		/**
		 * Registers a replacement class for a deprecated qualified class name.
		 * @param deprecatedClassQName The deprecated qualified class name.
		 * @param replacementClass The class that replaces the deprecated one.
		 */
		public static function registerDeprecatedClass(deprecatedClassQName:String, replacementClass:Class):void
		{
			_deprecatedLookup[deprecatedClassQName] = replacementClass;
			
			// handle case when package is not specified
			var shortName:String = deprecatedClassQName.substr(deprecatedClassQName.lastIndexOf(':') + 1);
			if (!_deprecatedLookup[shortName])
				_deprecatedLookup[shortName] = replacementClass;
			
			// make sure class can be looked up by name (in case it's an internal class)
			deprecatedClassQName = getQualifiedClassName(replacementClass);
			if (!getClassDefinition(deprecatedClassQName))
				_deprecatedLookup[deprecatedClassQName] = replacementClass;
		}

		/**
		 * @param classQName A qualified class name.
		 * @param implementsQName A qualified interface name.
		 * @return true if the class implements the interface, or if the two QNames are equal.
		 */
		public static function classImplements(classQName:String, implementsQName:String):Boolean
		{
			if (classQName == implementsQName)
				return true;
			try {
				if (!cacheClassInfo(classQName))
					return false;
				return classImplementsMap[classQName][implementsQName] !== undefined;
			} catch (e:Error) { trace(e.getStackTrace()); }
			return false;
		}
		
		/**
		 * @param classQName A qualified class name of a class in question.
		 * @param extendsQName A qualified class name that the class specified by classQName may extend.
		 * @return true if clasQName extends extendsQName, or if the two QNames are equal.
		 */
		public static function classExtends(classQName:String, extendsQName:String):Boolean
		{
			if (classQName == extendsQName)
				return true;
			try {
				if (!cacheClassInfo(classQName))
						return false;
				return classExtendsMap[classQName][extendsQName] !== undefined;
			} catch (e:Error) { trace(e.getStackTrace()); }
			return false;
		}
		
		/**
		 * @param classQName A qualified class name.
		 * @param isQName A qualified class or interface name.
		 * @return true if classQName extends or implements isQName, or if the two QNames are equal.
		 */
		public static function classIs(classQName:String, isQName:String):Boolean
		{
			return classImplements(classQName, isQName) || classExtends(classQName, isQName);
		}
		
		/**
		 * This function gets a list of all the interfaces implemented by a class.
		 * @param classQName A qualified class name.
		 * @return A list of qualified class names of interfaces that the given class implements.
		 */
		public static function getClassImplementsList(classQName:String):Array
		{
			cacheClassInfo(classQName);
			var result:Array = [];
			for (var name:String in classImplementsMap[classQName])
				result.push(name);
			return result;
		}
		
		/**
		 * This function gets a list of all the superclasses that a class extends.
		 * @param classQName A qualified class name.
		 * @return A list of qualified class names of interfaces that the given class extends.
		 */
		public static function getClassExtendsList(classQName:String):Array
		{
			cacheClassInfo(classQName);
			var result:Array = [];
			for (var name:String in classExtendsMap[classQName])
				result.push(name);
			return result;
		}
		
		/**
		 * This maps a qualified class name to an object.
		 * For each interface the class implements, the object maps the qualified class name of the interface to a value of true.
		 */
		private static const classImplementsMap:Object = new Object();

		/**
		 * This maps a qualified class name to an object.
		 * For each interface the class extends, the object maps the qualified class name of the interface to a value of true.
		 */
		private static const classExtendsMap:Object = new Object();
		
		/**
		 * avmplus.describeTypeJSON(o:*, flags:uint):Object
		 */
		private static const describeTypeJSON:Function = DescribeType.getJSONFunction();
		
		/**
		 * This function will populate the classImplementsMap and classExtendsMap for the given qualified class name.
		 * @param classQName A qualified class name.
		 * @return true if the class info has been cached.
		 */
		private static function cacheClassInfo(classQName:String):Boolean
		{
			if (classImplementsMap[classQName] != undefined && classExtendsMap[classQName] != undefined)
				return true; // already cached
			
			var classDef:Class = getClassDefinition(classQName);
			if (classDef == null)
				return false;

			var type:Object = describeTypeJSON(
				classDef,
				DescribeType.INCLUDE_TRAITS
					| DescribeType.USE_ITRAITS
					| DescribeType.INCLUDE_INTERFACES
					| DescribeType.INCLUDE_BASES
					| DescribeType.INCLUDE_METADATA
			);

			var iMap:Object = new Object();
			for each (var _implements:String in type.traits.interfaces)
				iMap[_implements] = true;
			classImplementsMap[classQName] = iMap;

			var eMap:Object = new Object();
			for each (var _extends:String in type.traits.bases)
				eMap[_extends] = true;
			classExtendsMap[classQName] = eMap;
			
			for each (var meta:Object in type.traits.metadata)
				if (meta.name == 'Deprecated')
					registerDeprecatedClass(classQName, classDef);
			
			return true; // successfully cached
		}
	}
}
