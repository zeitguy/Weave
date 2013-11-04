'use strict';

describe('Controller: ColorColumnPanelCtrl', function () {

  // load the controller's module
  beforeEach(module('AWSApp'));

  var ColorColumnPanelCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    ColorColumnPanelCtrl = $controller('ColorColumnPanelCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});

