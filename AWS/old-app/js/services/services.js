'use strict';

/* Services */


/**
 * Query Object Service provides access to the main "singleton" query object.
 *
 * Don't worry, it will be possible to manage more than one query object in the
 * future.
 */
angular.module("aws.services", []).service("queryobj", function () {
    this.title = "AlphaQueryObject";
    this.date = new Date();
    this.author = "UML IVPR AWS Team";
    this.computationEngine = "r";
    this.scriptType = "columns"
    this.dataTable = {id:1,title:"default"};
    this.conn = {
        serverType: 'MySQL',
        connectionType: 'RMySQL',
        sqlip: 'localhost',
        sqlport: '3306',
        sqldbname: 'sdoh2010q',
        sqluser: 'root',
        sqlpass: 'pass',
        schema: 'data',
        dsn: 'brfss'
    };
    var columnCategories = ["geography", "indicators", "byvars", "timeperiods", "analytics"];
    this.setQueryObject = function (jsonObj) {
        if (!jsonObj) {
            return undefined;
        }
        this.q = angular.copy(jsonObj);

    }
    return {
        q: this,
        title: this.title,
        date: this.date,
        author: this.author,
        dataTable: function () {
            return this.dataTable;
        },
        conn: this.conn,
        scriptType: this.scriptType,
        slideFilter: this.slideFilter,
        getSelectedColumnIds: function(){
            // loop through the possible column groups
            // given an id, go get the minimal column object
            // return that array of objects.
            var ary = [];
            var col = ["geography", "indicators", "byvars", "timeperiods", "analytics"];
            var temp;
            for (var i =0; i< col.length; i++){
                if (this[col[i]]){
                    angular.forEach(this[col[i]], function(item){
                        if (item.hasOwnProperty('id')){
                            ary.push(item.id);
                        } else{
                            ary.push(item);
                        }
                    });
                }
            }
            return ary;
        },
        getSelectedColumns: function () {
            //TODO hackity hack hack
            var col = ["geography", "indicators", "byvars", "timeperiods", "analytics"];
            var columns = [];
            var temp;
            for (var i = 0; i < col.length; i++) {
                if (this[col[i]]){
                	angular.forEach(this[col[i]], function(item){
                		if(item.hasOwnProperty('publicMetadata')) {
                			var obj = {
                       			title:item.publicMetadata.title,
	            				id:item.id,
	            				range:item.publicMetadata.var_range
                			};
                			columns.push(obj);
                		}
                	});
                }
            }
            return columns;
        }

    }


})

angular.module("aws.services").service("scriptobj", ['queryobj', '$rootScope', '$q', function (queryobj, scope, $q) {
   
    /**
     * This function wraps the async aws getListOfScripts function into an angular defer/promise
     * So that the UI asynchronously wait for the data to be available...
     */
    this.getListOfScripts = function () {
        
    	var deferred = $q.defer();

        aws.RClient.getListOfScripts(function (result) {
            
        	// since this function executes async in a future turn of the event loop, we need to wrap
            // our code into an $apply call so that the model changes are properly observed.
        	scope.$safeApply(function () {
                deferred.resolve(result);
            });
        	
        });
        
        // regardless of when the promise was or will be resolved or rejected,
        // then calls one of the success or error callbacks asynchronously as soon as the result
        // is available. The callbacks are called with a single argument: the result or rejection reason.
        return deferred.promise;
    };
    
    /**
     * This function wraps the async aws getListOfScripts function into an angular defer/promise
     * So that the UI asynchronously wait for the data to be available...
     */
    this.getScriptMetadata = function () {
        var deferred = $q.defer();

        aws.RClient.getScriptMetadata(queryobj.scriptSelected, function (result) {
        	
        	// since this function executes async in a future turn of the event loop, we need to wrap
            // our code into an $apply call so that the model changes are properly observed.
            scope.$safeApply(function () {
                deferred.resolve(result);
            });
            console.log(result);
        });
      
        // regardless of when the promise was or will be resolved or rejected,
 	    // then calls one of the success or error callbacks asynchronously as soon as the result
     	// is available. The callbacks are called with a single argument: the result or rejection reason.
        return deferred.promise;
    };
    var localmetadata = this.getScriptMetadata();
    this.getScriptInputs = function(){
    	var locdef = this.getScriptMetadata(); 
    	locdef.then(function(result){
    		return result.inputs
    	});	
    	return locdef;
    };
    
    
    
}]);

angular.module("aws.services").service("dataService", ['$q', '$rootScope', 'queryobj',
    function ($q, scope, queryobj) {


        var fetchColumns = function (table) {
            var deferred = $q.defer();
            var prom = deferred.promise;
            var deferred2 = $q.defer();
            if (!table.id) {
            	return deferred2.promise;
            }
            var id = table.id;
            var callbk = function (result) {
                scope.$safeApply(function () {
                    //console.log(result);
                    deferred.resolve(result);
                });
            };
            var callbk2 = function (result) {
                scope.$safeApply(function () {

                    console.log(result);
                    deferred2.resolve(result);
                });
            };

            aws.DataClient.getEntityChildIds(id, callbk);

            deferred.promise.then(function (res) {
                aws.DataClient.getDataColumnEntities(res, callbk2);
            });

            prom = deferred2.promise.then(function (response) {
                //console.log(response);
                return response;
            }, function (response) {
                console.log("error " + response);
            });

            return prom;
        };

        var fetchGeoms = function () {
            var deferred = $q.defer();
            var prom = deferred.promise;
            var deferred2 = $q.defer();
            var callbk = function (result) {
                scope.$safeApply(function () {
                    console.log(result);
                    deferred.resolve(result);
                });
            };
            var callbk2 = function (result) {
                scope.$safeApply(function () {

                    console.log(result);
                    deferred2.resolve(result);
                });
            };
            aws.DataClient.getEntityIdsByMetadata({"dataType": "geometry"}, callbk);
            deferred.promise.then(function (res) {
                aws.DataClient.getDataColumnEntities(res, callbk2);
            });

            prom = deferred2.promise.then(function (response) {
                //console.log(response);
                return response;
            }, function (response) {
                console.log("error " + response);
            });

            return prom;
        };

        var fetchTables = function(){
            var deferred = $q.defer();
            var callback = function(result){
                scope.$safeApply(function(){
                	// fetching tables callback
                    console.log(result);
                    deferred.resolve(result);
                });
            };
            aws.DataClient.getDataTableList(callback);
            return deferred.promise;
        };

        var fullColumnObjs = fetchColumns(queryobj.dataTable);
        var fullGeomObjs = fetchGeoms();
        var databaseTables = fetchTables();
        var filter = function (data, type) {
            var filtered = [];
            for (var i = 0; i < data.length; i++) {
                try {
                    if (data[i].publicMetadata.ui_type == type) {
                        filtered.push(data[i]);
                    }
                } catch (e) {
                    console.log(e);
                }
            }
            filtered.sort();
            return filtered;
        };

        return {
            giveMeColObjs: function (scopeobj) {
                return fullColumnObjs.then(function (response) {
                    var type = scopeobj.panelType;
                    return filter(response, type);
                });
            },
            refreshColumns: function (scopeobj) {
                fullColumnObjs = fetchColumns(queryobj.dataTable);
            },
            giveMeGeomObjs: function () {
                return fullGeomObjs.then(function (response) {
                    return response;
                });
            },
            giveMeTables: function(){
                return databaseTables.then(function(response)
                {
                    return response;
                });
            },
            getSelectedColumns: function(){
            	var cols = queryobj.getSelectedColumnIds();
            	var arr = [];
            	return fullColumnObjs.then(function(result){
	            	angular.forEach(result, function(item, i){
	            		var c = cols.indexOf(item.id);
	            		if (c >= 0){
	            			var col = { id: item.id,
				                        title: item.publicMetadata.title,
				                        range: item.publicMetadata.var_range,
				                        var_type: item.publicMetadata.ui_type,
				                        var_label: item.publicMetadata.var_label };
	            			arr.push(col);
	            		}
	            	});
                    return arr;
            	})
            	
            },
            giveMePrettyColsById: function(ids){
                return [].reduce(function(x){return x;}, fullColumnObjs.then(function(response){
                    response.forEach(function(item){
                    if (ids.indexOf(item.id)){
                        return { id: item.id,
                            title: item.publicMetadata.title,
                            range: item.publicMetadata.var_range,
                            var_type: item.publicMetadata.ui_type,
                            var_label: item.publicMetadata.var_label
                        };
                    }});
                }));
            }
        };
    }]);
