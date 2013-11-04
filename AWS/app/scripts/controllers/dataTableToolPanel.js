'use strict';

angular.module('AWSApp')
  .controller('DataTableToolPanelCtrl', function ($scope, QueryService) {
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
		QueryService.queryObject['DataTable'] = {};
		if ($scope.enabled == true) {
			if($scope.selection != "" && $scope.selection != undefined) {
				QueryService.queryObject['DataTable']['columns'] =  $.map($scope.selection, function(item){
					return angular.fromJson(item).param;
				});
			}
		} else {
			delete QueryService.queryObject['DataTable'];
			$scope.selection = "";
		}
		
	});
	
	$scope.$watch('selection', function() {
		if($scope.selection != "" && $scope.selection != undefined) {
			QueryService.queryObject['DataTable']['columns'] =  $.map($scope.selection, function(item){
				return angular.fromJson(item).param;
			});
		}
	});
  });
