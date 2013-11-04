'use strict';
/**
 * Left Panel Module LeftPanelCtrl - Manages the model for the left panel.
 */
angular.module('AWSApp')
  .controller('LeftPanelCtrl', function($scope, $location, QueryService, $q) {

        $scope.isActive = function(route) {
            return route == $location.path();
        };

        $scope.queryObject = angular.toJson(QueryService.queryObject, true);


        $scope.$watch(function () {
            return QueryService.queryObject;
        },function() {
            $scope.queryObject = angular.toJson(QueryService.queryObject, true);
        }, true);

        $scope.$watch(function() { return $scope.queryObject }, function() {
            QueryService.queryObject = angular.fromJson($scope.queryObject);
        }, true);

        $scope.shouldShow = false;
        var setCount = function(res) {
            $scope.shouldShow = res;
        };
        aws.addBusyListener(setCount);

    });
