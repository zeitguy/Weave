'use strict';

describe('Controller: BarChartToolPanelCtrl', function () {

  // load the controller's module
  beforeEach(module('AWSApp'));

  var BarChartToolPanelCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    BarChartToolPanelCtrl = $controller('BarChartToolPanelCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});

