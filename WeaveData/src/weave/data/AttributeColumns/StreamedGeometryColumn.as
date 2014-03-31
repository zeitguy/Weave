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
	import flash.utils.ByteArray;
	
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	import mx.utils.ObjectUtil;
	
	import weave.api.WeaveAPI;
	import weave.api.core.ICallbackCollection;
	import weave.api.data.ColumnMetadata;
	import weave.api.data.IQualifiedKey;
	import weave.api.newLinkableChild;
	import weave.api.primitives.IBounds2D;
	import weave.api.registerLinkableChild;
	import weave.api.reportError;
	import weave.api.services.IWeaveGeometryTileService;
	import weave.core.LinkableNumber;
	import weave.core.LinkableString;
	import weave.services.addAsyncResponder;
	import weave.services.beans.GeometryStreamMetadata;
	import weave.utils.AsyncSort;
	import weave.utils.GeometryStreamDecoder;
	
	/**
	 * StreamedGeometryColumn
	 * 
	 * @author adufilie
	 */
	public class StreamedGeometryColumn extends AbstractAttributeColumn
	{
		private static var _debug:Boolean = false;
		
		public function StreamedGeometryColumn(metadataTileDescriptors:ByteArray, geometryTileDescriptors:ByteArray, tileService:IWeaveGeometryTileService, metadata:Object = null)
		{
			super(metadata);
			
			_tileService = registerLinkableChild(this, tileService);
			
			_geometryStreamDecoder.keyType = metadata[ColumnMetadata.KEY_TYPE];
			
			// handle tile descriptors
			WeaveAPI.StageUtils.callLater(this, _geometryStreamDecoder.decodeMetadataTileList, [metadataTileDescriptors]);
			WeaveAPI.StageUtils.callLater(this, _geometryStreamDecoder.decodeGeometryTileList, [geometryTileDescriptors]);
			
			var self:Object = this;
			boundingBoxCallbacks.addImmediateCallback(this, function():void{
				if (_debug)
					debugTrace(self,'boundingBoxCallbacks',boundingBoxCallbacks,'keys',keys.length);
			});
			addImmediateCallback(this, function():void{
				if (_debug)
					debugTrace(self,'keys',keys.length);
			});
		}
		
		public function get boundingBoxCallbacks():ICallbackCollection
		{
			return _geometryStreamDecoder.metadataCallbacks;
		}
		
		override public function getMetadata(propertyName:String):String
		{
			return super.getMetadata(propertyName);
		}
		
		/**
		 * This is a list of unique keys this column defines values for.
		 */
		override public function get keys():Array
		{
			return _geometryStreamDecoder.keys;
		}
		
		override public function containsKey(key:IQualifiedKey):Boolean
		{
			return _geometryStreamDecoder.getGeometriesFromKey(key) != null;
		}
		
		/**
		 * @return The Array of geometries associated with the given key (if dataType not specified).
		 */
		override public function getValueFromKey(key:IQualifiedKey, dataType:Class=null):*
		{
			var value:* = _geometryStreamDecoder.getGeometriesFromKey(key);
			
			// cast to different types
			if (dataType == Boolean)
				value = (value is Array);
			else if (dataType == Number)
				value = value ? (value as Array).length : NaN;
			else if (dataType == String)
				value = value ? 'Geometry(' + key.keyType + '#' + key.localName + ')' : undefined;
			
			return value;
		}
		
		public function get collectiveBounds():IBounds2D
		{
			return _geometryStreamDecoder.collectiveBounds;
		}
		
		/**
		 * This function returns true if the column is still downloading tiles.
		 * @return True if there are tiles still downloading.
		 */
		public function isStillDownloading():Boolean
		{
			return _metadataStreamDownloadCounter > 0
				|| _geometryStreamDownloadCounter > 0;
		}
		
		private var _tileService:IWeaveGeometryTileService;
		private const _geometryStreamDecoder:GeometryStreamDecoder = newLinkableChild(this, GeometryStreamDecoder);
		
		private var _geometryStreamDownloadCounter:int = 0;
		private var _metadataStreamDownloadCounter:int = 0;
		
		
		public var metadataTilesPerQuery:int = 200; //10;
		public var geometryTilesPerQuery:int = 200; //30;
		
		public function requestGeometryDetail(dataBounds:IBounds2D, lowestImportance:Number):void
		{
			//trace("requestGeometryDetail",dataBounds,lowestImportance);
			if (dataBounds == null || isNaN(lowestImportance))
				return;
			
			// don't bother downloading if we know the result will be empty
			if (dataBounds.isEmpty())
				return;
			
			var metaRequestBounds:IBounds2D;
			var metaRequestImportance:Number;
			switch (metadataRequestMode.value)
			{
				case METADATA_REQUEST_MODE_ALL:
					metaRequestBounds = _geometryStreamDecoder.collectiveBounds;
					metaRequestImportance = 0;
					break;
				case METADATA_REQUEST_MODE_XY:
					metaRequestBounds = dataBounds;
					metaRequestImportance = 0;
					break;
				case METADATA_REQUEST_MODE_XYZ:
					metaRequestBounds = dataBounds;
					metaRequestImportance = lowestImportance;
					break;
			}
			// request metadata tiles
			var metadataTileIDs:Array = _geometryStreamDecoder.getRequiredMetadataTileIDs(metaRequestBounds, metaRequestImportance, true);
			// request geometry tiles needed for desired dataBounds and zoom level (filter by XYZ)
			var geometryTileIDs:Array = _geometryStreamDecoder.getRequiredGeometryTileIDs(dataBounds, lowestImportance, true);

			if (_debug)
			{
				if (metadataTileIDs.length > 0)
					debugTrace(this, "requesting metadata tiles: " + metadataTileIDs);
				if (geometryTileIDs.length > 0)
					debugTrace(this, "requesting geometry tiles: " + geometryTileIDs);
			}
			
			var query:AsyncToken;
			// make requests for groups of tiles
			while (metadataTileIDs.length > 0)
			{
				query = _tileService.getMetadataTiles(metadataTileIDs.splice(0, metadataTilesPerQuery));
				addAsyncResponder(query, handleMetadataStreamDownload, handleMetadataDownloadFault, query);
				
				_metadataStreamDownloadCounter++;
			}
			// make requests for groups of tiles
			while (geometryTileIDs.length > 0)
			{
				query = _tileService.getGeometryTiles(geometryTileIDs.splice(0, geometryTilesPerQuery));
				addAsyncResponder(query, handleGeometryStreamDownload, handleGeometryDownloadFault, query);
				_geometryStreamDownloadCounter++;
			} 
		}
		
		private function handleMetadataDownloadFault(event:FaultEvent, token:Object = null):void
		{
			if (!wasDisposed)
				reportError(event);
			//trace("handleDownloadFault",token,ObjectUtil.toString(event));
			_metadataStreamDownloadCounter--;
		}
		private function handleGeometryDownloadFault(event:FaultEvent, token:Object = null):void
		{
			if (!wasDisposed)
				reportError(event);
			//trace("handleDownloadFault",token,ObjectUtil.toString(event));
			_geometryStreamDownloadCounter--;
		}

		private function reportNullResult(token:Object):void
		{
			reportError("Did not receive any data from service for geometry column. " + token);
		}
		
		private var _totalDownloadedSize:int = 0;

		private function handleMetadataStreamDownload(event:ResultEvent, token:Object = null):void
		{
			_metadataStreamDownloadCounter--;
			
			if (event.result == null)
			{
				reportNullResult(token);
				return;
			}
			
			var result:ByteArray = event.result as ByteArray;
			_totalDownloadedSize += result.bytesAvailable;
			//trace("handleMetadataStreamDownload "+result.bytesAvailable,"total bytes "+_totalDownloadedSize);

			// when decoding finishes, run callbacks
			_geometryStreamDecoder.decodeMetadataStream(result);
		}
		
		private function handleGeometryStreamDownload(event:ResultEvent, token:Object = null):void
		{
			_geometryStreamDownloadCounter--;

			if (event.result == null)
			{
				reportNullResult(token);
				return;
			}

			var result:ByteArray = event.result as ByteArray;
			_totalDownloadedSize += result.bytesAvailable;
			//trace("handleGeometryStreamDownload "+result.bytesAvailable,"total bytes "+_totalDownloadedSize);

			// when decoding finishes, run callbacks
			_geometryStreamDecoder.decodeGeometryStream(result);
		}
		
		/**
		 * This mode determines which metadata tiles will be requested based on what geometry data is requested.
		 * Possible request modes are:<br>
		 *    all -> All metadata tiles, regardless of requested X-Y-Z range <br>
		 *    xy -> Metadata tiles contained in the requested X-Y range, regardless of Z range <br>
		 *    xyz -> Metadata tiles contained in the requested X-Y-Z range only <br>
		 */
		public static const metadataRequestMode:LinkableString = new LinkableString(METADATA_REQUEST_MODE_XYZ, verifyMetadataRequestMode);
		
		public static const METADATA_REQUEST_MODE_ALL:String = 'all';
		public static const METADATA_REQUEST_MODE_XY:String = 'xy';
		public static const METADATA_REQUEST_MODE_XYZ:String = 'xyz';
		public static function get metadataRequestModeEnum():Array
		{
			return [METADATA_REQUEST_MODE_ALL, METADATA_REQUEST_MODE_XY, METADATA_REQUEST_MODE_XYZ];
		}
		private static function verifyMetadataRequestMode(value:String):Boolean
		{
			return metadataRequestModeEnum.indexOf(value) >= 0;
		}
		
		/**
		 * This is the minimum bounding box screen area required for a geometry to be considered relevant.
		 */		
		public static const geometryMinimumScreenArea:LinkableNumber = new LinkableNumber(1, verifyMinimumScreenArea);
		private static function verifyMinimumScreenArea(value:Number):Boolean
		{
			return value >= 1;
		}
	}
}
