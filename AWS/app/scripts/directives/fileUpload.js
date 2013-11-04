'use strict';

angular.module('AWSApp')
  .directive('fileUpload', function () {
    return {
      template: '<div></div>',
      restrict: 'E',
      link: function postLink(scope, element, attrs) {
        element.text('this is the fileUpload directive');
      }
    };
  });
