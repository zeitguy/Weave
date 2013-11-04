'use strict';

angular.module('AWSApp')
  .controller('ColorColumnPanelCtrl', function ($scope, QueryService) {
   	$scope.$watch(function(){
		return QueryService.queryObject.scriptSelected;
	}, function() {
		if (QueryService.queryObject.hasOwnProperty('scriptSelected')) {
			$scope.options = QueryService.getScriptMetadata(QueryService.queryObject.scriptSelected).then(function(result){
				return result.outputs;
			});
		}
	});
	
	$scope.$watch('enabled', function() {
		QueryService.queryObject['ColorColumn'] = "";
		if ($scope.enabled == true) {
			if($scope.selection != "" && $scope.selection != undefined) {
					QueryService.queryObject['ColorColumn'] = angular.fromJson($scope.selection).param;
			}
		} else {
			delete QueryService.queryObject['ColorColumn'];
			$scope.selection = "";
		}
	});
	
	$scope.$watch('selection', function() {
		if($scope.selection != "" && $scope.selection != undefined) {
			if ($scope.enabled) {	
				QueryService.queryObject['ColorColumn'] = angular.fromJson($scope.selection).param;
			}
		}
	});
  });
