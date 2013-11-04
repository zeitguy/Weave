'use strict';

describe('Controller: WeaveCtrl', function () {

  // load the controller's module
  beforeEach(module('AWS'));

  var WeaveCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    WeaveCtrl = $controller('WeaveCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});
