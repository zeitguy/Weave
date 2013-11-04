'use strict';

describe('Controller: DataTableToolPanelCtrl', function () {

  // load the controller's module
  beforeEach(module('AWSApp'));

  var DataTableToolPanelCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    DataTableToolPanelCtrl = $controller('DataTableToolPanelCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});

