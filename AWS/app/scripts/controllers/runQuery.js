'use strict';

angular.module('AWSApp')
  .controller('RunQueryCtrl', function($scope, QueryService){
			
		var queryHandler = undefined;
		
		$scope.runQuery = function(){
			queryHandler = new aws.QueryHandler(QueryService.queryObject);
			queryHandler.runQuery();
		};
		
		$scope.clearWeave = function(){
			if (queryHandler) {
				queryHandler.clearWeave();
				queryHandler = undefined;
			}
		};
    });
