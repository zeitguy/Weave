'use strict';

describe('Service: Dataservice', function () {

  // load the service's module
  beforeEach(module('AWS'));

  // instantiate service
  var Dataservice;
  beforeEach(inject(function (_Dataservice_) {
    Dataservice = _Dataservice_;
  }));

  it('should do something', function () {
    expect(!!Dataservice).toBe(true);
  });

});
