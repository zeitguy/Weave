'use strict';

angular.module('AWSApp')
 /*var MainCtrl = */  .controller('MainCtrl',  function($scope, QueryService) {
        $scope.leftPanelUrl = "views/leftPanel.html";
        $scope.analysisUrl = "views/analysis.html";
        $scope.weaveInstancePanel = "views/weave.html";

        $scope.$watch(function(){
            return aws.timeLogString;
        },function(oldVal, newVal){
            $("#LogBox").append(newVal);
        });
        $scope.dataTableList = QueryService.getDataTableList();

        $scope.dataTable;

        $scope.$watch('dataTable', function() {
            if($scope.dataTable != "" && $scope.dataTable != undefined) {
                QueryService.queryObject.dataTable = angular.fromJson($scope.dataTable);
            }
        });
 }
)
;
