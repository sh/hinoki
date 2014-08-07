// Generated by CoffeeScript 1.7.1
(function() {
  var Promise, hinoki;
  hinoki = {};
  if (typeof window !== "undefined" && window !== null) {
    if (window.Promise == null) {
      throw new Error('hinoki requires Promise global by bluebird to be present');
    }
    Promise = window.Promise;
    window.hinoki = hinoki;
  } else if ((typeof module !== "undefined" && module !== null ? module.exports : void 0) != null) {
    Promise = require('bluebird');
    module.exports = hinoki;
  } else {
    throw new Error('either the `window` global or the `module.exports` global must be present');
  }
  hinoki.get = function(oneOrManyContainers, oneOrManyNamesOrPaths, debug) {
    var containers;
    containers = hinoki.arrayify(oneOrManyContainers);
    if (containers.length === 0) {
      throw new Error('at least 1 container is required');
    }
    if (Array.isArray(oneOrManyNamesOrPaths)) {
      return hinoki.getMany(containers, oneOrManyNamesOrPaths, debug);
    } else {
      return hinoki.getOne(containers, oneOrManyNamesOrPaths, debug);
    }
  };
  hinoki.getMany = function(containers, namesOrPaths, debug) {
    return Promise.all(namesOrPaths).map(function(nameOrPath) {
      return hinoki.getOne(containers, nameOrPath, debug);
    });
  };
  hinoki.getOne = function(containers, nameOrPath, debug) {
    var container, dependenciesPromise, dependencyNames, dependencyPaths, error, factory, factoryCallResultPromise, factoryResult, path, remainingContainers, underConstruction, valueResult, _ref;
    path = hinoki.castPath(nameOrPath);
    valueResult = hinoki.resolveValueInContainers(containers, path);
    if (valueResult != null) {
      if (typeof debug === "function") {
        debug({
          event: 'valueFound',
          name: path.name(),
          path: path.segments(),
          value: valueResult.value,
          container: valueResult.container
        });
      }
      return Promise.resolve(valueResult.value);
    }
    if (path.isCyclic()) {
      error = new hinoki.CircularDependencyError(path, containers[0]);
      return Promise.reject(error);
    }
    factoryResult = hinoki.resolveFactoryInContainers(containers, path, debug);
    if (factoryResult instanceof Error) {
      return Promise.reject(factoryResult);
    }
    if (factoryResult == null) {
      error = new hinoki.UnresolvableFactoryError(path, containers[0]);
      return Promise.reject(error);
    }
    factory = factoryResult.factory, container = factoryResult.container;
    if (typeof debug === "function") {
      debug({
        event: 'factoryFound',
        name: path.name(),
        path: path.segments(),
        factory: factory,
        container: container
      });
    }
    underConstruction = (_ref = container.underConstruction) != null ? _ref[path.name()] : void 0;
    if (underConstruction != null) {
      if (typeof debug === "function") {
        debug({
          event: 'valueUnderConstruction',
          name: path.name(),
          path: path.segments(),
          value: underConstruction,
          container: container
        });
      }
      return underConstruction;
    }
    remainingContainers = hinoki.startingWith(containers, container);
    dependencyNames = hinoki.getNamesToInject(factory);
    dependencyPaths = dependencyNames.map(function(x) {
      return hinoki.castPath(x).concat(path);
    });
    dependenciesPromise = hinoki.get(remainingContainers, dependencyPaths, debug);
    factoryCallResultPromise = dependenciesPromise.then(function(dependencyValues) {
      return hinoki.callFactory(container, path, factory, dependencyValues, debug);
    });
    if (container.underConstruction == null) {
      container.underConstruction = {};
    }
    container.underConstruction[path.name()] = factoryCallResultPromise;
    return factoryCallResultPromise.then(function(value) {
      if (hinoki.isUndefined(value)) {
        error = new hinoki.FactoryReturnedUndefinedError(path, container, factory);
        return Promise.reject(error);
      }
      if (container.values == null) {
        container.values = {};
      }
      container.values[path.name()] = value;
      delete container.underConstruction[path.name()];
      return value;
    });
  };
  hinoki.callFactory = function(container, nameOrPath, factory, dependencyValues, debug) {
    var error, exception, path, valueOrPromise;
    path = hinoki.castPath(nameOrPath);
    try {
      valueOrPromise = factory.apply(null, dependencyValues);
    } catch (_error) {
      exception = _error;
      error = new hinoki.ExceptionInFactoryError(path, container, exception);
      return Promise.reject(error);
    }
    if (!hinoki.isThenable(valueOrPromise)) {
      if (typeof debug === "function") {
        debug({
          event: 'valueCreated',
          name: path.name(),
          path: path.segments(),
          value: valueOrPromise,
          factory: factory,
          container: container
        });
      }
      return Promise.resolve(valueOrPromise);
    }
    if (typeof debug === "function") {
      debug({
        event: 'promiseCreated',
        name: path.name(),
        path: path.segments(),
        promise: valueOrPromise,
        container: container,
        factory: factory
      });
    }
    return Promise.resolve(valueOrPromise).then(function(value) {
      if (typeof debug === "function") {
        debug({
          event: 'promiseResolved',
          name: path.name(),
          path: path.segments(),
          value: value,
          container: container,
          factory: factory
        });
      }
      return value;
    })["catch"](function(rejection) {
      error = new hinoki.PromiseRejectedError(path, container, rejection);
      return Promise.reject(error);
    });
  };
  hinoki.resolveFactoryInContainer = function(container, nameOrPath, debug) {
    var accum, defaultResolver, name, path, resolve, resolvers;
    path = hinoki.castPath(nameOrPath);
    name = path.name();
    defaultResolver = function(container, name) {
      var factory;
      factory = hinoki.defaultFactoryResolver(container, name);
      if (typeof debug === "function") {
        debug({
          event: 'defaultFactoryResolverCalled',
          calledWithName: name,
          calledWithContainer: container,
          returnedFactory: factory
        });
      }
      return factory;
    };
    resolvers = container.factoryResolvers || [];
    accum = function(inner, resolver) {
      return function(container, name) {
        var factory;
        factory = resolver(container, name, inner, debug);
        if (typeof debug === "function") {
          debug({
            event: 'factoryResolverCalled',
            resolver: resolver,
            calledWithName: name,
            calledWithContainer: container,
            returnedFactory: factory
          });
        }
        return factory;
      };
    };
    resolve = resolvers.reduceRight(accum, defaultResolver);
    return resolve(container, name);
  };
  hinoki.resolveFactoryInContainers = function(containers, nameOrPath, debug) {
    var path;
    path = hinoki.castPath(nameOrPath);
    return hinoki.some(containers, function(container) {
      var factory;
      factory = hinoki.resolveFactoryInContainer(container, path, debug);
      if (factory == null) {
        return;
      }
      if ('function' !== typeof factory) {
        return new hinoki.FactoryNotFunctionError(path, container, factory);
      }
      return {
        factory: factory,
        container: container
      };
    });
  };
  hinoki.resolveValueInContainer = function(container, nameOrPath, debug) {
    var accum, defaultResolver, name, path, resolve, resolvers;
    path = hinoki.castPath(nameOrPath);
    name = path.name();
    defaultResolver = function(container, name) {
      var value;
      value = hinoki.defaultValueResolver(container, name);
      if (typeof debug === "function") {
        debug({
          event: 'defaultValueResolverCalled',
          calledWithName: name,
          calledWithContainer: container,
          returnedValue: value
        });
      }
      return value;
    };
    resolvers = container.valueResolvers || [];
    accum = function(inner, resolver) {
      return function(container, name) {
        var value;
        value = resolver(container, name, inner, debug);
        if (typeof debug === "function") {
          debug({
            event: 'valueResolverCalled',
            resolver: resolver,
            calledWithName: name,
            calledWithContainer: container,
            returnedValue: value
          });
        }
        return value;
      };
    };
    resolve = resolvers.reduceRight(accum, defaultResolver);
    return resolve(container, name);
  };
  hinoki.resolveValueInContainers = function(containers, nameOrPath, debug) {
    var path;
    path = hinoki.castPath(nameOrPath);
    return hinoki.some(containers, function(container) {
      var value;
      value = hinoki.resolveValueInContainer(container, path, debug);
      if (hinoki.isUndefined(value)) {
        return;
      }
      return {
        value: value,
        container: container
      };
    });
  };
  hinoki.newContainer = function(factories, values) {
    if (factories == null) {
      factories = {};
    }
    if (values == null) {
      values = {};
    }
    return {
      factories: factories,
      values: values
    };
  };
  hinoki.defaultValueResolver = function(container, name) {
    var _ref;
    return (_ref = container.values) != null ? _ref[name] : void 0;
  };
  hinoki.defaultFactoryResolver = function(container, name) {
    var factory, _ref;
    factory = (_ref = container.factories) != null ? _ref[name] : void 0;
    if (factory == null) {
      return;
    }
    if ((factory.$inject == null) && 'function' === typeof factory) {
      factory.$inject = hinoki.parseFunctionArguments(factory);
    }
    return factory;
  };
  hinoki.CircularDependencyError = function(path, container) {
    this.message = "circular dependency " + (path.toString());
    this.type = 'CircularDependencyError';
    this.name = path.name();
    this.path = path.segments();
    this.container = container;
    if (Error.captureStackTrace) {
      return Error.captureStackTrace(this, this.constructor);
    }
  };
  hinoki.CircularDependencyError.prototype = new Error;
  hinoki.UnresolvableFactoryError = function(path, container) {
    this.message = "unresolvable factory '" + (path.name()) + "' (" + (path.toString()) + ")";
    this.type = 'UnresolvableFactoryError';
    this.name = path.name();
    this.path = path.segments();
    this.container = container;
    if (Error.captureStackTrace) {
      return Error.captureStackTrace(this, this.constructor);
    }
  };
  hinoki.UnresolvableFactoryError.prototype = new Error;
  hinoki.ExceptionInFactoryError = function(path, container, exception) {
    this.message = "exception in factory '" + (path.name()) + "': " + exception;
    this.type = 'ExceptionInFactoryError';
    this.name = path.name();
    this.path = path.segments();
    this.container = container;
    this.exception = exception;
    if (Error.captureStackTrace) {
      return Error.captureStackTrace(this, this.constructor);
    }
  };
  hinoki.ExceptionInFactoryError.prototype = new Error;
  hinoki.PromiseRejectedError = function(path, container, rejection) {
    this.message = "promise returned from factory '" + (path.name()) + "' was rejected with reason: " + rejection;
    this.type = 'PromiseRejectedError';
    this.name = path.name();
    this.path = path.segments();
    this.container = container;
    this.rejection = rejection;
    if (Error.captureStackTrace) {
      return Error.captureStackTrace(this, this.constructor);
    }
  };
  hinoki.PromiseRejectedError.prototype = new Error;
  hinoki.FactoryNotFunctionError = function(path, container, factory) {
    this.message = "factory '" + (path.name()) + "' is not a function: " + factory;
    this.type = 'FactoryNotFunctionError';
    this.name = path.name();
    this.path = path.segments();
    this.container = container;
    this.factory = factory;
    if (Error.captureStackTrace) {
      return Error.captureStackTrace(this, this.constructor);
    }
  };
  hinoki.FactoryNotFunctionError.prototype = new Error;
  hinoki.FactoryReturnedUndefinedError = function(path, container, factory) {
    this.message = "factory '" + (path.name()) + "' returned undefined";
    this.type = 'FactoryReturnedUndefinedError';
    this.name = path.name();
    this.path = path.segments();
    this.container = container;
    this.factory = factory;
    if (Error.captureStackTrace) {
      return Error.captureStackTrace(this, this.constructor);
    }
  };
  hinoki.FactoryReturnedUndefinedError.prototype = new Error;
  hinoki.PathPrototype = {
    toString: function() {
      return this.$segments.join(' <- ');
    },
    name: function() {
      return this.$segments[0];
    },
    segments: function() {
      return this.$segments;
    },
    concat: function(otherValue) {
      var otherPath, segments;
      otherPath = hinoki.castPath(otherValue);
      segments = this.$segments.concat(otherPath.$segments);
      return hinoki.newPath(segments);
    },
    isCyclic: function() {
      return hinoki.arrayOfStringsHasDuplicates(this.$segments);
    }
  };
  hinoki.newPath = function(segments) {
    var path;
    path = Object.create(hinoki.PathPrototype);
    path.$segments = segments;
    return path;
  };
  hinoki.castPath = function(value) {
    if (hinoki.PathPrototype.isPrototypeOf(value)) {
      return value;
    } else if ('string' === typeof value) {
      return hinoki.newPath([value]);
    } else if (Array.isArray(value)) {
      return hinoki.newPath(value);
    } else {
      throw new Error("value " + value + " can not be cast to name");
    }
  };
  hinoki.isObject = function(x) {
    return x === Object(x);
  };
  hinoki.isThenable = function(x) {
    return hinoki.isObject(x) && 'function' === typeof x.then;
  };
  hinoki.isUndefined = function(x) {
    return 'undefined' === typeof x;
  };
  hinoki.isNull = function(x) {
    return null === x;
  };
  hinoki.isExisting = function(x) {
    return x != null;
  };
  hinoki.identity = function(x) {
    return x;
  };
  hinoki.some = function(array, iterator, predicate, sentinel) {
    var i, length, result;
    if (iterator == null) {
      iterator = hinoki.identity;
    }
    if (predicate == null) {
      predicate = hinoki.isExisting;
    }
    if (sentinel == null) {
      sentinel = void 0;
    }
    i = 0;
    length = array.length;
    while (i < length) {
      result = iterator(array[i], i);
      if (predicate(result, i)) {
        return result;
      }
      i++;
    }
    return sentinel;
  };
  hinoki.arrayOfStringsHasDuplicates = function(array) {
    var i, length, value, valuesSoFar;
    i = 0;
    length = array.length;
    valuesSoFar = {};
    while (i < length) {
      value = array[i];
      if (Object.prototype.hasOwnProperty.call(valuesSoFar, value)) {
        return true;
      }
      valuesSoFar[value] = true;
      i++;
    }
    return false;
  };
  hinoki.arrayify = function(arg) {
    if (Array.isArray(arg)) {
      return arg;
    }
    if (arg == null) {
      return [];
    }
    return [arg];
  };
  hinoki.startingWith = function(xs, x) {
    var index;
    index = xs.indexOf(x);
    if (index === -1) {
      return [];
    }
    return xs.slice(index);
  };
  hinoki.parseFunctionArguments = function(fun) {
    var argumentPart, dependencies, string;
    if ('function' !== typeof fun) {
      throw new Error('argument must be a function');
    }
    string = fun.toString();
    argumentPart = string.slice(string.indexOf('(') + 1, string.indexOf(')'));
    dependencies = argumentPart.match(/([^\s,]+)/g);
    if (dependencies) {
      return dependencies;
    } else {
      return [];
    }
  };
  return hinoki.getNamesToInject = function(factory) {
    if (factory.$inject != null) {
      return factory.$inject;
    } else {
      return hinoki.parseFunctionArguments(factory);
    }
  };
})();
