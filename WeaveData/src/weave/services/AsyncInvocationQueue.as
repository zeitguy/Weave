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

package weave.services
{
	import flash.events.Event;
	
	import mx.rpc.events.ResultEvent;
	
	import weave.api.WeaveAPI;
	import weave.api.core.IDisposableObject;
	import weave.api.core.ILinkableObjectWithBusyStatus;
	import weave.api.objectWasDisposed;
	import weave.api.reportError;
	
	/**
	 * this class contains functions that handle a queue of remote procedure calls
	 * 
	 * @author adufilie
	 */
	public class AsyncInvocationQueue implements ILinkableObjectWithBusyStatus, IDisposableObject
	{
		public static var debug:Boolean = false;
		
		/**
		 * @param paused When set to true, no queries will be executed until begin() is called.
		 */
		public function AsyncInvocationQueue(paused:Boolean = false)
		{
			_paused = paused;
		}
		
		public function isBusy():Boolean
		{
			assertQueueValid();
			return _downloadQueue.length > 0;
		}
		
		public function dispose():void
		{
			assertQueueValid();
			_downloadQueue.length = 0;
		}
		
		private var _paused:Boolean = false;
		
		/**
		 * If the 'paused' constructor parameter was set to true, use this function to start invoking queued queries.
		 */		
		public function begin():void
		{
			assertQueueValid();
			
			if (_paused)
			{
				_paused = false;
				
				for each (var query:ProxyAsyncToken in _downloadQueue)
					WeaveAPI.ProgressIndicator.addTask(query);
				
				if (_downloadQueue.length)
					performQuery(_downloadQueue[0]);
			}
		}

		// interface to add a query to the download queue. 
		public function addToQueue(query:ProxyAsyncToken):void
		{
			assertQueueValid();
			
			//trace("addToQueue",query);
			
			// if this query has already been queued, then do not queue it again
			if (_downloadQueue.indexOf(query) >= 0)
			{
				//trace("already queued", query);
				return;
			}
			
			if (!_paused)
				WeaveAPI.ProgressIndicator.addTask(query);
			
			if (debug)
			{
				addAsyncResponder(
					query,
					function(event:ResultEvent, token:Object = null):void
					{
						weaveTrace('Query returned: ' + query);
						//weaveTrace('Query returned: ' + query, ObjectUtil.toString(event.result));
					},
					function(..._):void
					{
						weaveTrace('Query failed: ' + query);
					}
				);
			}

			
			_downloadQueue.push(query);
			
			if (!_paused && _downloadQueue.length == 1)
			{
				//trace("downloading immediately", query);
				performQuery(query);
			}
			else
			{
				//trace("added to queue", query);
			}
		}
	
		// Queue to handle concurrent requests to be downloaded.
		private var _downloadQueue:Array = new Array();

		// perform a query in the queue
		protected function performQuery(query:ProxyAsyncToken):void
		{
			assertQueueValid();
			
			//trace("performQuery (timeout = "+query.webService.requestTimeout+")",query.toString());
			addAsyncResponder(query, handleQueryResultOrFault, handleQueryResultOrFault, query);
			
			//URLRequestUtils.reportProgress = false;
			
			if (debug)
				weaveTrace('Query sent: ' + query);
			
			query.invoke();
			
			//URLRequestUtils.reportProgress = true;
		}
		
		// This function gets called when a query has been downloaded.  It will download the next query if available
		protected function handleQueryResultOrFault(event:Event, query:ProxyAsyncToken):void
		{
			if (objectWasDisposed(this))
				return;
			
			WeaveAPI.ProgressIndicator.removeTask(query);
			
			// see if the query is in the queue
			var index:int = _downloadQueue.indexOf(query);
			// stop if query not found in queue
			if (index < 0)
			{
				reportError("Query not found in queue: " + query);
				return;
			}
			
			//trace("remove from queue (position "+index+", length: "+_downloadQueue.length+")", query);
			
			// remove the query from the queue
			_downloadQueue.splice(index, 1);
			
			// if the position was 0, start downloading the next query
			if (index == 0 && _downloadQueue.length > 0)
			{
				//trace("perform next query", _downloadQueue[0] as DelayedAsyncCall);
				// get the next item in the list
				performQuery(_downloadQueue[0]);
			}
			return;
		}
		
		private function assertQueueValid():void
		{
			if (objectWasDisposed(this))
				throw new Error("AsyncInvocationQueue was already disposed");
		}
	}
}
