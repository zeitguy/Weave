'use strict';

angular.module('AWSApp')
    .controller('MapToolPanelCtrl', function($scope, QueryService) {
        $scope.options = QueryService.getGeometryDataColumnsEntities();

        $scope.$watch('enabled', function() {
            if ($scope.enabled == true) {
                QueryService.queryObject['MapTool'] = {};
                if ($scope.selection != "") {
                    var metadata = angular.fromJson($scope.selection);
                    if (metadata != "" && metadata != undefined) {
                        if ($scope.enabled) {
                            QueryService.queryObject['MapTool'] = {
                                id: metadata.id,
                                title: metadata.publicMetadata.title,
                                keyType: metadata.publicMetadata.keyType
                            };
                        }
                    }
                }
            } else {
                delete QueryService.queryObject['MapTool'];
                $scope.selection = "";
            }

        });

        $scope.$watch('selection', function() {
            if ($scope.selection != "") {
                var metadata = angular.fromJson($scope.selection);
                if (metadata != "" && metadata != undefined) {
                    if ($scope.enabled) {
                        QueryService.queryObject['MapTool'] = {
                            weaveEntityId: metadata.id,
                            title: metadata.publicMetadata.title,
                            keyType: metadata.publicMetadata.keyType
                        };
                    }
                }
            }
        });
    });