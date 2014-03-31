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
	/**
	 * LinkableBoolean, LinkableString and LinkableNumber contain simple, immutable data types.  LinkableXML
	 * is an exception because it contains an XML object that can be manipulated.  Changes to the internal
	 * XML object cannot be detected automatically, so a detectChanges() function is provided.  However, if
	 * two LinkableXML objects have the same internal XML object, modifying the internal XML of one object
	 * would inadvertently modify the internal XML of another.  To avoid this situation, LinkableXML creates
	 * a copy of the XML that you set as the session state.
	 * 
	 * @author adufilie
	 * @see weave.core.LinkableVariable
	 */
	public class LinkableXML extends LinkableVariable
	{
		public function LinkableXML(allowNull:Boolean = true)
		{
			super(String, verifyXMLString);
			_allowNull = allowNull;
		}
		
		private var _allowNull:Boolean;
		
		private function verifyXMLString(value:String):Boolean
		{
			if (value == null)
				return _allowNull;
			
			try {
				XML(value);
				return true;
			}
			catch (e:*) { }
			return false;
		}

		/**
		 * This function will run the callbacks attached to this LinkableXML if the session state has changed.
		 * This function should be called if the XML is modified without calling set value() or setSessionState().
		 */
		public function detectChanges():void
		{
			value = value;
		}

		/**
		 * This is the sessioned XML value for this object.
		 */
		public function get value():XML
		{
			// validate local XML version of the session state String if necessary
			if (_prevTriggerCount != triggerCounter)
			{
				_prevTriggerCount = triggerCounter;
				_sessionStateXML = null;
				try
				{
					if (_sessionState) // false if empty string (prefer null over empty xml)
						_sessionStateXML = XML(_sessionState);
				}
				catch (e:Error)
				{
					// xml parsing failed, so keep null
				}
			}
			return _sessionStateXML;
		}
		/**
		 * This will save a COPY of the value passed in to prevent multiple LinkableXML objects from having the same internal XML object.
		 * @param value An XML to copy and save as the sessioned value for this object.
		 */		
		public function set value(value:XML):void
		{
			var str:String = value ? value.toXMLString() : null;
			setSessionState(str);
		}
		
		override public function setSessionState(value:Object):void
		{
			if (value && value.hasOwnProperty(XML_STRING))
				value = value[XML_STRING];
			if (value is XML)
				value = (value as XML).toXMLString();
			super.setSessionState(value);
		}
		
		override public function getSessionState():Object
		{
			// return an XMLString wrapper object for use with WeaveXMLEncoder.
			var result:Object = {};
			result[XML_STRING] = _sessionState;
			return result;
		}
		
		public static const XML_STRING:String = "XMLString";

		/**
		 * This is used to store an XML value, which is separate from the actual session state String.
		 */
		private var _sessionStateXML:XML = null;
		
		/**
		 * This is the trigger count at the time when _sessionStateXML was last updated.
		 */		
		private var _prevTriggerCount:uint = triggerCounter;
		
		/**
		 * Converts a session state object to XML the same way a LinkableXML object would.
		 */
		public static function xmlFromState(state:Object):XML
		{
			if (state && state.hasOwnProperty(XML_STRING))
				state = state[XML_STRING];
			return XML(state);
		}
	}
}
