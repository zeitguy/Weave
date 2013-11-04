'use strict';

describe('Controller: RunQueryCtrl', function () {

  // load the controller's module
  beforeEach(module('AWSApp'));

  var RunQueryCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    RunQueryCtrl = $controller('RunQueryCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});
