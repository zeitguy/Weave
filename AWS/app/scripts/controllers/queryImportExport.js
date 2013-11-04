'use strict';

angular.module('AWSApp')
  .controller('QueryImportExportCtrl', function($scope, QueryService) {

        $scope.queryObject = angular.toJson(QueryService.queryObject, true);

        $scope.$watch(function () {
            return QueryService.queryObject;
        },function() {
            $scope.queryObject = angular.toJson(QueryService.queryObject, true);
        }, true);

        $scope.exportQueryObject = function(queryObject) {
            var blob = new Blob([ JSON.stringify(queryObject, undefined, 2) ], {
                type : "text/plain;charset=utf-8"
            });
            saveAs(blob, "QueryObject.json");
        };

        $scope.importQueryObject = function() {
        };

        $scope.$on('newQueryLoaded', function(e) {
            $scope.$safeApply(function() {
                if ($scope.queryObject) {
                    QueryService.queryObject = $scope.queryObject;
                }
            });
        });
    });
