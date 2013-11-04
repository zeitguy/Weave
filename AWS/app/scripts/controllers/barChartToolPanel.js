'use strict';

angular.module('AWSApp')
  .controller('BarChartToolPanelCtrl', function ($scope, QueryService) {
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
		QueryService.queryObject['BarChartTool'] = {};
		if ($scope.enabled == true) {
			if($scope.sortSelection != "" && $scope.sortSelection != undefined) {
					QueryService.queryObject['BarChartTool']['sort'] = angular.fromJson($scope.sortSelection).param;
			}
			if($scope.heightSelection != "" && $scope.heightSelection != undefined) {
				QueryService.queryObject['BarChartTool']['heights'] =  $.map($scope.heightSelection, function(item){
					return angular.fromJson(item).param;
				});
			}
			if($scope.labelSelection != "" && $scope.labelSelection != undefined) {
				QueryService.queryObject['BarChartTool']['label'] = angular.fromJson($scope.labelSelection).param;
			}
		} else {
			delete QueryService.queryObject['BarChartTool'];
			$scope.sortSelection = "";
			$scope.heightSelection = "";
			$scope.labelSelection = "";
		}
		
	});
	
	$scope.$watch('sortSelection', function() {
		if($scope.sortSelection != "" && $scope.sortSelection != undefined) {
			if ($scope.enabled) {	
				QueryService.queryObject['BarChartTool']['sort'] = angular.fromJson($scope.sortSelection).param;
			}
		}
	});
	
	$scope.$watch('heightSelection', function() {
		if($scope.heightSelection != "" && $scope.heightSelection != undefined) {
			if ($scope.enabled) {	
				QueryService.queryObject['BarChartTool']['heights'] =  $.map($scope.heightSelection, function(item){
					return angular.fromJson(item).param;
				});
			}
		}
	});
	
	$scope.$watch('labelSelection', function() {
		if($scope.labelSelection != "" && $scope.labelSelection != undefined) {
			if ($scope.enabled) {	
				QueryService.queryObject['BarChartTool']['label'] = angular.fromJson($scope.labelSelection).param;
			}
		}
	});
  });
