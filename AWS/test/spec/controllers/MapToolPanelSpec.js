'use strict';

describe('Controller: MapToolPanelCtrl', function () {

  // load the controller's module
  beforeEach(module('AWSApp'));

  var MapToolPanelCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    MapToolPanelCtrl = $controller('MapToolPanelCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});

