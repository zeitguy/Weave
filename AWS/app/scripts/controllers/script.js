'use strict';

angular.module('AWSApp')
  .controller('ScriptCtrl', function($scope, QueryService){

       // array of column selected
    $scope.selection = []; 
    
    // array of filter types, can either be categorical (true) or continuous (false).
    $scope.filterType = [];
    
    // array of boolean values, true when the column it is possible to apply a filter on the column, 
    // we basically check if the metadata has varType, min, max etc...
    $scope.show = [];
    
    // the slider options for the columns, min, max etc... Array of object, comes from the metadata
    $scope.sliderOptions = [];
    
    // the categorical options for the columns, Array of string Arrays, comes from metadata, 
    // this is provided in the ng-repeat for the select2
    $scope.categoricalOptions = [];
    
    // array of filter values. This is used for the model and is sent to the queryObject, each element is either
    // [min, max] or ["a", "b", "c", etc...]
    $scope.filterValues = [];
    
    // array of booleans, either true of false if we want filtering enabled
    $scope.enabled = [];
    
    $scope.scriptList = QueryService.getListOfScripts();
    
    $scope.$watch('scriptSelected', function() {
        if($scope.scriptSelected != undefined) {
            if($scope.scriptSelected != ""){
                QueryService.queryObject['scriptSelected'] = $scope.scriptSelected;
                $scope.inputs = QueryService.getScriptMetadata($scope.scriptSelected).then(function(result){            // reinitialize and apply to model
                    $scope.scriptType = result.scriptType;
                    QueryService.queryObject['scriptType'] = result.scriptType;
                    return result.inputs;
                });
            }
        }
        // reset these values when the script changes
        $scope.selection = []; 
        $scope.filterType = [];
        $scope.show = [];
        $scope.sliderOptions = [];
        $scope.categoricalOptions = [];
        $scope.filterValues = [];
        $scope.enabled = [];
    });
    
    $scope.columns = [];
    
    $scope.$watch(function(){
        return QueryService.queryObject.dataTable;
    }, function(){
            if(QueryService.queryObject.hasOwnProperty("dataTable")) {
                if(QueryService.queryObject.dataTable.hasOwnProperty("id")) {
                    $scope.columns = QueryService.getDataColumnsEntitiesFromId(QueryService.queryObject.dataTable.id).then(function(result){
                        var orderedColumns = {};
                        for(var i = 0; i  < result.length; i++) {
                            if (result[i].publicMetadata.hasOwnProperty("aws_metadata")) {
                                var aws_metadata = angular.fromJson(result[i].publicMetadata.aws_metadata);
                                if(aws_metadata.hasOwnProperty("columnType")) {
                                    var key = aws_metadata.columnType;
                                    if(!orderedColumns.hasOwnProperty(key)) {
                                        orderedColumns[key] = [result[i]];
                                    } else {
                                        orderedColumns[key].push(result[i]);
                                    }
                                }
                            }
                        }
                        return orderedColumns;
                    });
                }
                if($scope.scriptSelected != undefined) {
                    if($scope.scriptSelected != ""){
                        QueryService.queryObject['scriptSelected'] = $scope.scriptSelected;
                        $scope.inputs = QueryService.getScriptMetadata($scope.scriptSelected).then(function(result){            // reinitialize and apply to model
                            return result.inputs;
                        });
                    }
                }
            }
            // reset these values when the data table changes
            $scope.selection = []; 
            $scope.filterType = [];
            $scope.show = [];
            $scope.sliderOptions = [];
            $scope.categoricalOptions = [];
            $scope.filterValues = [];
            $scope.enabled = [];
    }, true);
        
    $scope.$watch('selection', function(){
        QueryService.queryObject['FilteredColumnRequest'] = [];
        for(var i = 0; i < $scope.selection.length; i++) {
            QueryService.queryObject['FilteredColumnRequest'][i] = {};
            if($scope.selection != undefined) {
                if ($scope.selection[i] != ""){
                    var selection = angular.fromJson($scope.selection[i]);
                    
                    QueryService.queryObject['FilteredColumnRequest'][i] = {
                                                                            id : selection.id,
                                                                            filters : []
                                                                        };

                    var column = angular.fromJson($scope.selection[i]);
                    
                    if(column.publicMetadata.hasOwnProperty("aws_metadata")) {
                        var metadata = angular.fromJson(column.publicMetadata.aws_metadata);
                        if (metadata.hasOwnProperty("varType")) {
                            if (metadata.varType == "continuous") {
                                $scope.filterType[i] = "continuous"; // false for continuous, true for categorical
                                if(metadata.hasOwnProperty("varRange")) {
                                    $scope.show[i] = true;
                                    $scope.sliderOptions[i] = { range:true, min: metadata.varRange[0], max: metadata.varRange[1]};
                                }
                            } else if (metadata.varType == "categorical") {
                                $scope.filterType[i] = "categorical"; // false for continuous, true for categorical
                                if(metadata.hasOwnProperty("varValues")) {
                                    $scope.show[i] = true;
                                    $scope.categoricalOptions[i] = metadata.varValues;
                                }
                            }
                        }
                    } else {
                        // disable these when there is no aws_metadata
                        $scope.show[i] = false;
                        $scope.sliderOptions[i] = [];
                        $scope.categoricalOptions[i] = [];
                    }
                    
                } // end if ""
            } // end if undefined
            if($scope.filterValues != undefined) {
                if(($scope.filterValues != undefined) && $scope.filterValues != "") {
                    if($scope.filterValues[i] != undefined) {
                        var temp = $.map($scope.filterValues[i],function(item){
                            if (angular.fromJson(item).hasOwnProperty("value")) {
                                return angular.fromJson(item).value;
                            }
                            else {
                                return angular.fromJson(item);
                            }
                        });
                        
                        if ($scope.filterType[i] == "categorical") { 
                            QueryService.queryObject.FilteredColumnRequest[i].filters = temp;
                        } else if ($scope.filterType[i] == "continuous") { // continuous, we want arrays of ranges
                            QueryService.queryObject.FilteredColumnRequest[i].filters = [temp];
                        }
                    }
                }
            }
        } // end for
    }, true);
    
    $scope.$watch('filterValues', function(){
        for(var i = 0; i < $scope.selection.length; i++) {
            if(($scope.filterValues != undefined) && $scope.filterValues != "") {
                if($scope.filterValues[i] != undefined && $scope.filterValues[i] != []) {
                    
                    var temp = $.map($scope.filterValues[i],function(item){
                        if (angular.fromJson(item).hasOwnProperty("value")) {
                            return angular.fromJson(item).value;
                        }
                        else {
                            return angular.fromJson(item);
                        }                   
                    });
                    
                    if ($scope.filterType[i] == "categorical") { 
                        QueryService.queryObject.FilteredColumnRequest[i].filters = temp;
                    } else if ($scope.filterType[i] == "continuous") { // continuous, we want arrays of ranges
                        QueryService.queryObject.FilteredColumnRequest[i].filters = [temp];
                    }
                
                } else {
                    if (QueryService.queryObject.FilteredColumnRequest[i].hasOwnProperty("id")) {
                        QueryService.queryObject.FilteredColumnRequest[i].filters = [];
                    }
                }
            }
        }
    }, true);
    $scope.$watch('enabled', function(){
        for(var i = 0; i < $scope.selection.length; i++) {
            if(($scope.enabled != undefined) && $scope.enabled != []) {
                if($scope.enabled[i] != undefined && $scope.enabled == true) {
                    var temp = $.map($scope.filterValues[i],function(item){
                        if (angular.fromJson(item).hasOwnProperty("value")) {
                            return angular.fromJson(item).value;
                        }
                        else {
                            return angular.fromJson(item);
                        }                   
                    });
                    QueryService.queryObject.FilteredColumnRequest[i].filters = temp;
                } else if($scope.enabled[i] == undefined || $scope.enabled[i] == false) {
                        if(QueryService.queryObject.FilteredColumnRequest[i]) {
                            if (QueryService.queryObject.FilteredColumnRequest[i].hasOwnProperty("id")) {
                                $scope.filterValues[i] = null;
                            }
                        }
                 }
            } 
        }
    }, true);
});
