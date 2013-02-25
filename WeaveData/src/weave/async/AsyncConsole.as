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

package weave.async
{
	import flash.events.Event;
	
	import mx.core.UIComponent;
	
	import weave.cpp.CModule;
	import weave.cpp.vfs.ISpecialFile;
	
	public class AsyncConsole extends UIComponent implements ISpecialFile
	{
		public function AsyncConsole()
		{
			addEventListener(Event.ADDED_TO_STAGE, initCode);
		}
		
		private function initCode(e:Event):void
		{
			CModule.rootSprite = this;
			
			if( CModule.runningAsWorker() )
				return;
			
			trace("Initializing async console");
			CModule.vfs.console = this;
			CModule.startAsync(this);
		}
		
		public function write(fd:int, bufPtr:int, nbyte:int, errnoPtr:int):int
		{
			var str:String = CModule.readString(bufPtr, nbyte);
			trace(str);
			return nbyte;
		}
		public function read(fd:int, bufPtr:int, nbyte:int, errnoPtr:int):int { return 0; }
		public function fcntl(fd:int, com:int, data:int, errnoPtr:int):int { return 0; }
		public function ioctl(fd:int, com:int, data:int, errnoPtr:int):int { return 0; }
	}	
}