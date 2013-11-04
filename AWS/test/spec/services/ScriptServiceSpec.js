'use strict';

describe('Service: Scriptservice', function () {

  // load the service's module
  beforeEach(module('AWS'));

  // instantiate service
  var Scriptservice;
  beforeEach(inject(function (_Scriptservice_) {
    Scriptservice = _Scriptservice_;
  }));

  it('should do something', function () {
    expect(!!Scriptservice).toBe(true);
  });

});
