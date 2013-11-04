'use strict';

var app = angular.module('app', [
  'ngCookies',
  'ngResource',
  'ngSanitize',
  'ngRoute',
  'AWSApp,'
  'ui.bootstrap',
  'ui.select2',
  'ui.slider',
]);

app.run(['$rootScope', function($rootScope){
    $rootScope.$safeApply = function(fn, $scope) {
        if($scope == undefined){
            $scope = $rootScope;
        }

        fn = fn || function() {};
        if ( !$scope.$$phase ) {
            $scope.$apply( fn );
        }
        else {
            fn();
        }
    };
}]);

app.config(function ($routeProvider) {
    $routeProvider
      /*.when('/', {
        templateUrl: 'views/main.html',
        controller: 'MainCtrl'
      })*/
      .when('/visualization', {
        templateUrl: 'views/visualization.html',
        controller: 'VisualizationCtrl'
      })
      .when('/analysis', {
        templateUrl: 'views/analysis.html',
        controller: 'AnalysisCtrl'
      })
      .otherwise({
        redirectTo: '/'
      });
  });

