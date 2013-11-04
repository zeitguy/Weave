'use strict';

describe('Controller: FrankCtrl', function () {

  // load the controller's module
  beforeEach(module('AWSApp'));

  var FrankCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    FrankCtrl = $controller('FrankCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});

