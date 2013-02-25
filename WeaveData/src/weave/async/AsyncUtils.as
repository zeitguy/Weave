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
	import weave.api.WeaveAPI;
	import weave.api.core.IAsyncUtils;
	import weave.api.reportError;
	import weave.utils.DebugTimer;
	
	public class AsyncUtils implements IAsyncUtils
	{
		public static const RETURNED_ARGS:Array = ["RETURNED_ARGS"];
		private var ret:* = null;
		
		public function AsyncUtils()
		{
		}
		
		public function startTask(iterateFunction:Function, callback:Function, iterateFunctionArgs:Array = null, callbackFunctionArgs:Array = null):void
		{
			DebugTimer.begin();
			ret = iterateFunction.apply(null, iterateFunctionArgs);
			DebugTimer.end("iter func");
			
			runCallback(callback, callbackFunctionArgs);
		}
		
		private function runCallback(callback:Function, callbackFunctionArgs:Array = null):void
		{
			if( ret == null )
			{
				WeaveAPI.StageUtils.callLater(this, runCallback, arguments);
			} 
			else if( ret == 0 )
			{
				if( callbackFunctionArgs == RETURNED_ARGS )
					callback.apply(null, ret);
				else
					callback.apply(null, callbackFunctionArgs);
			} 
			else
			{
				var e:Error = new Error("Error within async thread", ret);
				reportError(e);
			}
		}
	}
}
