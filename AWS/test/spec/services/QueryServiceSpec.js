'use strict';

describe('Service: Queryservice', function () {

  // load the service's module
  beforeEach(module('AWS'));

  // instantiate service
  var Queryservice;
  beforeEach(inject(function (_Queryservice_) {
    Queryservice = _Queryservice_;
  }));

  it('should do something', function () {
    expect(!!Queryservice).toBe(true);
  });

});
