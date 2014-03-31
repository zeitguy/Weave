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

package weave.data.DataSources
{
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	import mx.utils.ObjectUtil;
	
	import weave.api.WeaveAPI;
	import weave.api.data.ColumnMetadata;
	import weave.api.data.DataTypes;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IDataSource;
	import weave.api.data.IQualifiedKey;
	import weave.api.disposeObject;
	import weave.api.newLinkableChild;
	import weave.api.registerLinkableChild;
	import weave.api.reportError;
	import weave.compiler.Compiler;
	import weave.core.LinkableBoolean;
	import weave.core.LinkableString;
	import weave.data.AttributeColumns.GeometryColumn;
	import weave.data.AttributeColumns.NumberColumn;
	import weave.data.AttributeColumns.ProxyColumn;
	import weave.data.AttributeColumns.StringColumn;
	import weave.primitives.GeneralizedGeometry;
	import weave.primitives.GeometryType;
	import weave.services.WFSServlet;
	import weave.services.addAsyncResponder;
	import weave.utils.BLGTreeUtils;
	import weave.utils.HierarchyUtils;
	
	/**
	 * 
	 * @author skolman
	 * @author adufilie
	 */
	public class WFSDataSource extends AbstractDataSource
	{
		WeaveAPI.registerImplementation(IDataSource, WFSDataSource, "WFS server");
		
		public function WFSDataSource()
		{
			url.addImmediateCallback(this, handleURLChange);
		}
		
		public const url:LinkableString = newLinkableChild(this, LinkableString);
		public const swapXY:LinkableBoolean = registerLinkableChild(this, new LinkableBoolean(true));
		public const useURLsInGetCapabilities:LinkableBoolean = registerLinkableChild(this, new LinkableBoolean(true), handleURLChange);
		
		private var wfsDataService:WFSServlet = null;
		
		private function handleURLChange():void
		{
			if (url.value == null)
				url.value = '/geoserver/wfs';
			disposeObject(wfsDataService);
			
			//TODO: dispose of all old columns, too
			
			wfsDataService = registerLinkableChild(this, new WFSServlet(url.value, useURLsInGetCapabilities.value));
		}
		
		override protected function initialize():void
		{
			// backwards compatibility
			if(_attributeHierarchy.value != null)
			{
				for each (var tag:XML in _attributeHierarchy.value.descendants("attribute"))
				{
					if (String(tag.@featureTypeName) == '')
					{
						tag.@featureTypeName = tag.@featureType;
						delete tag["@featureType"];
						tag.@dataType = _convertOldDataType(tag.@dataType);
					}
				}
				super.convertOldHierarchyFormat(_attributeHierarchy.value, 'attribute', {'projectionSRS': ColumnMetadata.PROJECTION});
			}
			
			super.initialize();
		}
		private function _convertOldDataType(value:String):String
		{
			if (value == 'Geometry')
				return DataTypes.GEOMETRY;
			if (value == 'String')
				return DataTypes.STRING;
			if (value == 'Number')
				return DataTypes.NUMBER;
			return value;
		}
		
		/**
		 * @param layerName Layer you want to query
		 * @param queryPoint Point around which to perform radius query.
		 * @param distance Value of radius
		 */
//		public function radiusSearch(layerName:String, queryPoint:Point,distance:Number):AsyncToken
//		{
//			var filterQuery:String = "<Filter><DWithin><PropertyName>the_geom</PropertyName><Point><coordinates>" + queryPoint.y + "," + queryPoint.x + "</coordinates></Point><Distance>" + distance + "</Distance></DWithin></Filter>";
//			var asyncToken:AsyncToken = wfsDataService.getFilteredQueryResult(layerName, ["STATE_FIPS"], filterQuery);
//			
//			return asyncToken;
//		}

		/**
		 * @param subtreeNode Specifies a subtree in the hierarchy to download.
		 */
		override protected function requestHierarchyFromSource(subtreeNode:XML=null):void
		{
			var query:AsyncToken;
			
			if (subtreeNode == null) // download top-level hierarchy 
			{
				query = wfsDataService.getCapabilties();

				addAsyncResponder(query, handleGetCapabilities, handleGetCapabilitiesError);
			}
			else // download a list of properties for a given featureTypeName
			{
				var dataTableName:String = subtreeNode.attribute("name").toString();
				
				query = wfsDataService.describeFeatureType(dataTableName);
				
				addAsyncResponder(query, handleDescribeFeature, handleDescribeFeatureError, subtreeNode);
			}
		}
		
		/**
		 * @param event
		 */
		private function handleGetCapabilities(event:ResultEvent, token:Object = null):void
		{
			var owsNS:String = 'http://www.opengis.net/ows';
			var wfsNS:String = 'http://www.opengis.net/wfs';
			var xml:XML;
			try
			{
				xml = XML(event.result);
				var rootTitle:String = xml.descendants(new QName(owsNS, 'ProviderName')).text().toXMLString();
				var root:XML = <hierarchy name={ rootTitle }/>;
				var featureTypeNames:XMLList = xml.descendants(new QName(wfsNS, 'FeatureType'));
				for (var i:int = 0; i < featureTypeNames.length(); i++)
				{
					var type:XML = featureTypeNames[i];
					var defaultSRS:String = type.child(new QName(wfsNS, 'DefaultSRS')).text().toXMLString();
					var categoryName:String = type.child(new QName(wfsNS, 'Name')).text().toXMLString();
					var categoryTitle:String = type.child(new QName(wfsNS, 'Title')).text().toXMLString();
					var category:XML = <category name={ categoryName } title={ categoryTitle } defaultSRS={ defaultSRS }/>;
					root.appendChild(category);
				}
				_attributeHierarchy.value = root;
			}
			catch (e:Error)
			{
				reportError("Received invalid XML from WFS service at "+url.value);
				if (xml)
					trace(xml.toXMLString());
				return;
			}
		}
		
		/**
		 * @param event
		 */
		private function handleGetCapabilitiesError(event:FaultEvent, token:Object = null):void
		{
			reportError(event);
		}
		
		/**
		 * @param event
		 * @param node This is the subtreeNode XML.
		 */
		private function handleDescribeFeature(event:ResultEvent, node:XML):void
		{
			node = HierarchyUtils.findEquivalentNode(_attributeHierarchy.value, node);
			if (!node)
				return;

			try
			{
				var result:XML = new XML(event.result);
			}
			catch (e:Error)
			{
				reportError(e, null, event.result);
				return;
			}

			var XMLSchema:String = "http://www.w3.org/2001/XMLSchema";
			// get a list of feature properties
			var rootQName:QName = new QName(XMLSchema, "complexType");
			var propertiesQName:QName = new QName(XMLSchema, "element");
			var propertiesList:XMLList = result.descendants(rootQName).descendants(propertiesQName);
			
			// define the hierarchy

			var featureTypeName:String = node.attribute("name").toString();

			for(var i:int = 0; i < propertiesList.length(); i++)
			{
				//trace(i,propertiesList[i].toXMLString());
				var propertyName:String = propertiesList[i].attribute("name");
				var propertyType:String = propertiesList[i].attribute("type");
				// handle case for   <xs:simpleType><xs:restriction base="xs:string"><xs:maxLength value="2"/></xs:restriction></xs:simpleType>
				// convert missing propertyType to string
				if (propertyType == '')
					propertyType = "xs:string";
				var dataType:String;
				switch (propertyType)
				{
					case "gml:MultiSurfacePropertyType":
					case "gml:MultiLineStringPropertyType":
					case "gml:MultiCurvePropertyType":
					case "gml:PointPropertyType":
						dataType = DataTypes.GEOMETRY;
						break;
					case "xsd:string":
					case "xs:string":
						dataType = DataTypes.STRING;
						break;
					default:
						dataType = DataTypes.NUMBER;
				}
				/**
				 * 'keyType' is used to differentiate this feature from others.
				 * 'featureTypeName' corresponds to the feature in WFS to get data for. 
				 * 'name' corresponds to the name of a column in the WFS feature data.
				 */
				var attrNode:XML = <attribute
						dataType={ dataType }
						keyType={ featureTypeName }
						title={ propertyName }
						name={ propertyName }
						featureTypeName={ featureTypeName }
					/>;
				if (dataType == DataTypes.GEOMETRY)
				{
					var defaultSRS:String = node.@defaultSRS;
					var array:Array = defaultSRS.split(':');
					var prevToken:String = '';
					while (array.length > 2)
						prevToken = array.shift();
					var proj:String = array.join(':');
					var altProj:String = prevToken;
					if (array.length > 1)
						altProj += ':' + array[1];
					if (!WeaveAPI.ProjectionManager.projectionExists(proj) && WeaveAPI.ProjectionManager.projectionExists(altProj))
						proj = altProj;
					attrNode['@'+ColumnMetadata.PROJECTION] = proj;
				}
				node.appendChild(attrNode);
			}
			_attributeHierarchy.detectChanges();
		}
		
		/**
		 * 
		 */
		private function handleDescribeFeatureError(event:FaultEvent, token:Object = null):void
		{
			reportError(event);
		}

		/**
		 * @inheritDoc
		 */
		override protected function requestColumnFromSource(proxyColumn:ProxyColumn):void
		{
			addAsyncResponder(
				wfsDataService.getFeature(proxyColumn.getMetadata("featureTypeName"), [proxyColumn.getMetadata("name")]),
				handleColumnDownload,
				handleColumnDownloadFail,
				proxyColumn
			);
		}
		
		private function getQName(xmlContainingNamespaceInfo:XML, qname:String):QName
		{
			var array:Array = String(qname).split(":");
			if (array.length != 2)
				return null;
			var prefix:String = array[0];
			var localName:String = array[1];
			var ns:* = xmlContainingNamespaceInfo.namespace(prefix);
			if (ns)
				return new QName(ns.uri, localName);
			return null;
		}

		private function handleColumnDownload(event:ResultEvent, proxyColumn:ProxyColumn):void
		{
			if (proxyColumn.wasDisposed)
				return;
			
			var result:XML = null;
			var i:int;
			try
			{
				try
				{
					result = new XML(event.result);
				}
				catch (e:Error)
				{
					trace(e.getStackTrace());
				}
	
				if (result == null || result.localName().toString() == 'ExceptionReport')
					throw new Error("An invalid XML result was received from the WFS service at "+this.url.value);
	
				var featureTypeName:String = proxyColumn.getMetadata('featureTypeName'); // typeName was previously stored here
				var propertyName:String = proxyColumn.getMetadata('name'); // propertyName was previously stored here
				var dataType:String = proxyColumn.getMetadata('dataType');
				var keyType:String = proxyColumn.getMetadata('keyType');
	
				//trace("WFSDataSource.handleColumnDownload(): typeName=" + featureTypeName + ", propertyName=" + propertyName);
				
				var gmlURI:String = "http://www.opengis.net/gml";
	
				// get QName for record id and data XML tags
				// The typeName string is something like topp:states, where topp is the namespace and states is the layer name
				// this QName refers the nodes having the gml:id attribute
				var keyQName:QName = getQName(result, featureTypeName);
				if (keyQName == null)
				{
					reportError('WFS response did not contain namespace of featureTypeName: ' + Compiler.stringify(proxyColumn.getProxyMetadata()));
					return;
				}
				var dataQName:QName = new QName(keyQName.uri, propertyName); // use same namespace as keyQName
	
				// get keys and data
				var keysList:XMLList = result.descendants(keyQName);
				var dataList:XMLList = result.descendants(dataQName);
	
				// process keys into a vector
				var keysVector:Vector.<IQualifiedKey> = new Vector.<IQualifiedKey>(keysList.length());
				for(i = 0; i < keysList.length(); i++)
				{
					keysVector[i] = WeaveAPI.QKeyManager.getQKey(keyType, keysList[i].attributes());
					//trace(keysList[i].attributes() + " --> "+ dataList[i].toString());
				}
				
				// determine the data type, and create the appropriate type of IAttributeColumn
				var newColumn:IAttributeColumn;
				if (ObjectUtil.stringCompare(dataType, DataTypes.GEOMETRY, true) == 0)
				{
					newColumn = new GeometryColumn(proxyColumn.getProxyMetadata());
					var geomVector:Vector.<GeneralizedGeometry> = new Vector.<GeneralizedGeometry>();
					var features:XMLList = result.descendants(keyQName);
					var firstFeatureData:XML = features[0].descendants(dataQName)[0];
					var geomType:String = firstFeatureData.children()[0].name().toString();
					if (geomType == (gmlURI + "::Point"))
						geomType = GeometryType.POINT;
					else if (geomType.indexOf(gmlURI + "::") == 0 && (geomType.indexOf('LineString') >= 0 || geomType.indexOf('Curve') >= 0))
						geomType = GeometryType.LINE;
					else
						geomType = GeometryType.POLYGON;
					var gmlPos:QName = new QName(gmlURI, geomType == GeometryType.POINT ? 'pos' : 'posList');
					
					swapXY.addGroupedCallback(
						newColumn,
						function():void
						{
							for (var geometryIndex:int = 0; geometryIndex < keysVector.length; geometryIndex++)
							{
								var gmlPosXMLList:XMLList = dataList[geometryIndex].descendants(gmlPos);
								var coordStr:String = '';
								for (i = 0; i < gmlPosXMLList.length(); i++)
								{
									if (i > 0)
										coordStr += ' ';
									coordStr += gmlPosXMLList[i].toString();
								}
								var coordinates:Array = coordStr.split(' ');
								
								if (swapXY.value)
								{
									// swap order (y,x to x,y)
									for (i = 0; i < coordinates.length; i += 2)
									{
										var temp:Number = coordinates[i+1];
										coordinates[i+1] = coordinates[i];
										coordinates[i] = temp;
									}
								}
								var geometry:GeneralizedGeometry = new GeneralizedGeometry(geomType);
								
								geometry.setCoordinates(coordinates, BLGTreeUtils.METHOD_SAMPLE);
								geomVector[geometryIndex] = geometry;
							}
							(newColumn as GeometryColumn).setGeometries(keysVector, geomVector);
						},
						true
					);
				}
				else if (ObjectUtil.stringCompare(dataType, DataTypes.NUMBER, true) == 0)
				{
					newColumn = new NumberColumn(proxyColumn.getProxyMetadata());
					(newColumn as NumberColumn).setRecords(keysVector, xmlToVector(dataList, new Vector.<Number>()));
				}
				else
				{
					newColumn = new StringColumn(proxyColumn.getProxyMetadata());
					(newColumn as StringColumn).setRecords(keysVector, xmlToVector(dataList, new Vector.<String>()));
				}
				// save pointer to new column inside the matching proxy column
				proxyColumn.setInternalColumn(newColumn);
			}
			catch (e:Error)
			{
				//var detail:String = ObjectUtil.toString(request.request) + '\n\nResult: ' + (result && result.toXMLString());
				reportError(e, null, result);
			}
		}
		
		/**
		 * Copies elements from XMLList to Vector
		 * @param xmlList source
		 * @param vector destination
		 * @return vector 
		 */
		private function xmlToVector(xmlList:XMLList, vector:*):*
		{
			vector.length = xmlList.length();
			for (var i:int = vector.length; i--;)
				vector[i] = xmlList[i];
			return vector;
		}
		
		private function handleColumnDownloadFail(event:FaultEvent, token:Object = null):void
		{
			reportError(event);
		}
	}
}

import flash.net.URLRequest;

import weave.data.AttributeColumns.ProxyColumn;

/**
 * This object is used as a token in an AsyncResponder.
 */
internal class ColumnRequestToken
{
	public function ColumnRequestToken(pathInHierarchy:XML, proxyColumn:ProxyColumn, request:URLRequest = null)
	{
		this.pathInHierarchy = pathInHierarchy;
		this.proxyColumn = proxyColumn;
		this.request = request;
	}
	public var pathInHierarchy:XML;
	public var proxyColumn:ProxyColumn;
	public var request:URLRequest;
	public var subtreeNode:XML;
}
