((root, factory) ->
  # amd
  if ('function' is typeof define) and define.amd?
    define(['bluebird', 'lodash'], factory)
  # nodejs
  else if exports?
    module.exports = factory(
      require('bluebird')
      require('lodash')
      require('fs')
      require('path')
    )
  # other
  else
    root.hinoki = factory(root.Promise, root.lodash)
)(this, (Promise, _, fs, path) ->

################################################################################
# get

  # polymorphic
  hinoki = (arg1, arg2, arg3) ->
    source = hinoki.source arg1

    if arg3?
      lifetimes = hinoki.coerceToArray arg2
      nameOrNamesOrFunction = arg3
    else
      lifetimes = [{}]
      nameOrNamesOrFunction = arg2

    cacheTarget = 0

    if 'function' is typeof nameOrNamesOrFunction
      names = hinoki.getNamesToInject(nameOrNamesOrFunction)
      paths = names.map(hinoki.coerceToArray)
      return hinoki.getValuesAndCacheTarget(
        source,
        lifetimes,
        paths,
        cacheTarget
      ).promise.spread(nameOrNamesOrFunction)

    if Array.isArray nameOrNamesOrFunction
      names = hinoki.coerceToArray(nameOrNamesOrFunction)
      paths = names.map(hinoki.coerceToArray)
      return hinoki.getValuesAndCacheTarget(
        source,
        lifetimes,
        paths,
        cacheTarget
      ).promise

    path = hinoki.coerceToArray(nameOrNamesOrFunction)
    return hinoki.getValueAndCacheTarget(
      source,
      lifetimes,
      path,
      cacheTarget
    ).promise

  # monomorphic
  hinoki.PromiseAndCacheTarget = (promise, cacheTarget) ->
    this.promise = promise
    this.cacheTarget = cacheTarget
    return this

  # monomorphic
  hinoki.getValuesAndCacheTarget = (source, lifetimes, paths, cacheTarget) ->
    # result.cacheTarget is determined synchronously
    nextCacheTarget = cacheTarget
    # result.promise is fulfilled asynchronously
    promise = Promise.all(_.map(paths, (path) ->
      result = hinoki.getValueAndCacheTarget(
        source
        lifetimes
        path
        cacheTarget
      )
      nextCacheTarget = Math.max(nextCacheTarget, result.cacheTarget)
      return result.promise
    ))
    return new hinoki.PromiseAndCacheTarget promise, nextCacheTarget

  # monomorphic
  hinoki.getValueAndCacheTarget = (source, lifetimes, path, cacheTarget) ->
    name = path[0]
    # look if there already is a value for that name in one of the lifetimes
    valueIndex = hinoki.getIndexOfFirstObjectHavingProperty lifetimes, name
    if valueIndex?
      valueOrPromise = lifetimes[valueIndex][name]
      promise =
        if hinoki.isThenable valueOrPromise
          # if the value is already being constructed
          # wait for that instead of starting a second construction.
          valueOrPromise
        else
          Promise.resolve valueOrPromise
      return new hinoki.PromiseAndCacheTarget promise, valueIndex

    # we have no value
    # look if there is a factory for that name in the source
    factory = source(name)
    unless factory?
      return new hinoki.PromiseAndCacheTarget(
        Promise.reject(new hinoki.UnresolvableError(path))
        cacheTarget
      )

    # we've got a factory.
    # let's check for cycles first since
    # we can't use the factory if the path contains a cycle.

    # TODO check if a value introduces a cycle to speed this up
    # already in
    if hinoki.arrayOfStringsHasDuplicates path
      # TODO we dont know the lifetime here
      return new hinoki.PromiseAndCacheTarget(
        Promise.reject(new hinoki.CircularDependencyError(path, {}, factory))
        cacheTarget
      )

    # no cycle - yeah!

    # lets make a value

    # first lets resolve the dependencies of the factory

    dependencyNames = hinoki.baseGetNamesToInject factory, true

    newPath = path.slice()

    dependencyPaths = dependencyNames.map (x) ->
      hinoki.coerceToArray(x).concat newPath

    # this code is reached synchronously from the start of the function call
    # without interleaving.

    if dependencyPaths.length isnt 0
      result = hinoki.getValuesAndCacheTarget(
        source,
        lifetimes,
        dependencyPaths,
        cacheTarget
      )
      dependenciesPromise = result.promise
      nextCacheTarget = result.cacheTarget
    else
      dependenciesPromise = Promise.resolve([])
      nextCacheTarget = cacheTarget

    factoryCallResultPromise = dependenciesPromise.then (dependencyValues) ->
      # the dependencies are ready!
      # we can finally call the factory!

      return hinoki.callFactoryAndNormalizeResult(
        lifetimes,
        newPath,
        factory,
        dependencyValues,
        nextCacheTarget
      )

    # cache the promise:
    # this code is reached synchronously from the start of the function call
    # without interleaving.
    # its important that the factoryCallResultPromise is added
    # to lifetimes[maxCacheTarget] synchronously
    # because as soon as control is given back to the sheduler
    # another process might request the value as well.
    # this way that process just reuses the factoryCallResultPromise
    # instead of building it all over again.

    unless factory.__nocache
      lifetimes[nextCacheTarget][name] = factoryCallResultPromise

    returnPromise = factoryCallResultPromise
      .then (value) ->
        # note that a null value is allowed!
        if hinoki.isUndefined value
          return Promise.reject(new hinoki.FactoryReturnedUndefinedError(newPath, {}, factory))

        # cache
        unless factory.__nocache
          lifetimes[nextCacheTarget][name] = value

        return value
      .catch (error) ->
        # prevent errored promises from being reused
        # and allow further requests for the errored names to succeed.
        unless factory.__nocache
          delete lifetimes[nextCacheTarget][name]
        return Promise.reject error

    return new hinoki.PromiseAndCacheTarget(returnPromise, nextCacheTarget)

  hinoki.callFactoryFunction = (factoryFunction, valuesOfDependencies) ->
    try
      valueOrPromise = factoryFunction.apply null, valuesOfDependencies
    catch error
      return Promise.reject new hinoki.ThrowInFactoryError path, {}, factoryFunction, error

  hinoki.callFactoryObjectArray = (factoryObject, dependenciesObject) ->
    iterator = (f) ->
      if 'function' is typeof f
        names = hinoki.getNamesToInject f
        dependencies = _.map names, (name) ->
          dependenciesObject[name]
        hinoki.callFactoryFunction f, dependencies
      else
        # supports nesting
        hinoki.callFactoryObjectArray(f, dependenciesObject)

    if Array.isArray factory
      Promise.all(factory).map(iterator)
    # object !
    else
      Promise.props _.mapValues factory, iterator

  # normalizes sync and async values returned by factories
  hinoki.callFactoryAndNormalizeResult = (lifetime, path, factory, dependencyValues) ->
    if 'function' is typeof factory
      valueOrPromise = hinoki.callFactoryFunction factory, dependencyValues
    else
      names = hinoki.getNamesToInject factory
      dependenciesObject = _.zipObject names, dependencyValues
      valueOrPromise = hinoki.callFactoryObjectArray factory, dependenciesObject

    # TODO also return directly if promise is already fulfilled
    unless hinoki.isThenable valueOrPromise
      # valueOrPromise is not a promise but an value
      # lifetime.debug? {
      #   event: 'valueWasCreated',
      #   path: path
      #   value: valueOrPromise
      #   factory: factory
      # }
      return Promise.resolve valueOrPromise

    # valueOrPromise is a promise

    # lifetime.debug? {
    #   event: 'promiseWasCreated'
    #   path: path
    #   promise: valueOrPromise
    #   factory: factory
    # }

    Promise.resolve(valueOrPromise)
      .then (value) ->
        # lifetime.debug? {
        #   event: 'promiseWasResolved'
        #   path: path
        #   value: value
        #   factory: factory
        # }
        return value
      .catch (rejection) ->
        Promise.reject new hinoki.PromiseRejectedError path, lifetime, rejection

################################################################################
# errors

  hinoki.inherits = (constructor, superConstructor) ->
    if 'function' is typeof Object.create
      constructor.prototype = Object.create(superConstructor.prototype)
      constructor.prototype.constructor = constructor
    else
      # if there is no Object.create we use a proxyConstructor
      # to make a new object that has superConstructor as its prototype
      # and make it the prototype of constructor
      proxyConstructor = ->
      proxyConstructor.prototype = superConstructor.prototype
      constructor.prototype = new proxyConstructor
      constructor.prototype.constructor = constructor

  # constructors for errors which are catchable with bluebirds `catch`

  # the base error for all other hinoki errors
  # not to be instantiated directly
  hinoki.BaseError = ->
  hinoki.inherits hinoki.BaseError, Error

  hinoki.UnresolvableError = (path, lifetime) ->
    this.name = 'UnresolvableError'
    this.message = "unresolvable name '#{path[0]}' (#{hinoki.pathToString path})"
    if Error.captureStackTrace?
      # second argument excludes the constructor from inclusion in the stack trace
      Error.captureStackTrace(this, this.constructor)

    this.path = path
    this.lifetime = lifetime
    return

  hinoki.inherits hinoki.UnresolvableError, hinoki.BaseError

  hinoki.CircularDependencyError = (path, lifetime, factory) ->
    this.name = 'CircularDependencyError'
    this.message = "circular dependency #{hinoki.pathToString path}"
    if Error.captureStackTrace?
      Error.captureStackTrace(this, this.constructor)

    this.path = path
    this.lifetime = lifetime
    this.factory = factory
    return

  hinoki.inherits hinoki.CircularDependencyError, hinoki.BaseError

  hinoki.ThrowInFactoryError = (path, lifetime, factory, error) ->
    this.name = 'ThrowInFactoryError'
    this.message = "error in factory for '#{path[0]}'. original error: #{error.toString()}"
    if Error.captureStackTrace?
      Error.captureStackTrace(this, this.constructor)

    this.path = path
    this.lifetime = lifetime
    this.factory = factory
    this.error = error
    return

  hinoki.inherits hinoki.ThrowInFactoryError, hinoki.BaseError

  hinoki.FactoryReturnedUndefinedError = (path, lifetime, factory) ->
    this.name = 'FactoryReturnedUndefinedError'
    this.message = "factory for '#{path[0]}' returned undefined"
    if Error.captureStackTrace?
      Error.captureStackTrace(this, this.constructor)

    this.path = path
    this.lifetime = lifetime
    this.factory = factory
    return

  hinoki.inherits hinoki.FactoryReturnedUndefinedError, hinoki.BaseError

  hinoki.PromiseRejectedError = (path, lifetime, error) ->
    this.name = 'PromiseRejectedError'
    this.message = "promise returned from factory for '#{path[0]}' was rejected. original error: #{error.toString()}"
    if Error.captureStackTrace?
      Error.captureStackTrace(this, this.constructor)

    this.path = path
    this.lifetime = lifetime
    this.error = error
    return

  hinoki.inherits hinoki.PromiseRejectedError, hinoki.BaseError

################################################################################
# path

  hinoki.pathToString = (path) ->
    path.join ' <- '

################################################################################
# util

  hinoki.isObject = (x) ->
    x is Object(x)

  hinoki.isThenable = (x) ->
    hinoki.isObject(x) and 'function' is typeof x.then

  hinoki.isUndefined =  (x) ->
    'undefined' is typeof x

  hinoki.isNull = (x) ->
    null is x

  hinoki.isExisting = (x) ->
    x?

  hinoki.identity = (x) ->
    x

  # returns whether an array of strings contains duplicates.
  #
  # complexity: O(n) since hash lookup is O(1)

  hinoki.arrayOfStringsHasDuplicates = (array) ->
    i = 0
    length = array.length
    valuesSoFar = {}
    while i < length
      value = array[i]
      if Object.prototype.hasOwnProperty.call valuesSoFar, value
        return true
      valuesSoFar[value] = true
      i++
    return false

  # coerces `arg` into an array.
  #
  # returns `arg` if it is an array.
  # returns `[arg]` otherwise.
  # returns `[]` if `arg` is null.
  #
  # example:
  # coerceToArray 'a'
  # => ['a']

  hinoki.coerceToArray = (arg) ->
    if Array.isArray arg
      return arg
    unless arg?
      return []
    [arg]

  # example:
  # parseFunctionArguments (a, b c) ->
  # => ['a', 'b‘, 'c']

  hinoki.parseFunctionArguments = (fun) ->
    unless 'function' is typeof fun
      throw new Error 'argument must be a function'

    string = fun.toString()

    argumentPart = string.slice(string.indexOf('(') + 1, string.indexOf(')'))

    dependencies = argumentPart.match(/([^\s,]+)/g)

    if dependencies
      dependencies
    else
      []

  hinoki.getNamesToInject = (factory) ->
    hinoki.baseGetNamesToInject factory, false

  hinoki.baseGetNamesToInject = (factory, cache) ->
    if factory.__inject?
      return factory.__inject
    else if 'function' is typeof factory
      names = hinoki.parseFunctionArguments factory
      if cache
        factory.__inject = names
      return names
    else if Array.isArray factory or 'object' is typeof factory
      namesSet = {}
      _.forEach factory, (subFactory) ->
        subNames = hinoki.baseGetNamesToInject(subFactory, cache)
        _.forEach subNames, (subName) ->
          namesSet[subName] = true
      names = Object.keys(namesSet)
      if cache
        factory.__inject = names
      return names
    else
      throw new Error 'factory has to be a function, object of factories or array of factories'

  hinoki.getIndexOfFirstObjectHavingProperty = (objects, property) ->
    index = -1
    length = objects.length
    while ++index < length
      # TODO maybe use hasownproperty
      unless hinoki.isUndefined objects[index][property]
        return index
    return null

################################################################################
# functions for working with sources

  # returns an object containing all the exported properties
  # of all `*.js` and `*.coffee` files in `filepath`.
  # if `filepath` is a directory recurse into every file and subdirectory.

  if fs? and path?
    hinoki.requireSource = (filepath) ->
      unless 'string' is typeof filepath
        throw new Error 'argument must be a string'
      hinoki.baseRequireSource filepath, {}

    # TODO call this something like fromExports
    hinoki.baseRequireSource = (filepath, object) ->
      stat = fs.statSync(filepath)
      if stat.isFile()
        extension = path.extname(filepath)

        if extension isnt '.js' and extension isnt '.coffee'
          return

        # coffeescript is only required on demand when the project contains .coffee files
        # in order to support pure javascript projects
        if extension is '.coffee'
          require('coffee-script/register')

        extension = require(filepath)

        Object.keys(extension).map (key) ->
          unless 'function' is typeof extension[key]
            throw new Error('export is not a function: ' + key + ' in :' + filepath)
          if object[key]?
            throw new Error('duplicate export: ' + key + ' in: ' + filepath + '. first was in: ' + object[key].$file)
          object[key] = extension[key]
          # add filename as metadata
          object[key].$file = filepath

      else if stat.isDirectory()
        filenames = fs.readdirSync(filepath)
        filenames.forEach (filename) ->
          hinoki.baseRequireSource path.join(filepath, filename), object

      return object

  hinoki.source = (arg) ->
    if 'function' is typeof arg
      arg
    else if Array.isArray arg
      coercedSources = arg.map hinoki.source
      (name) ->
        # try all sources in order
        index = -1
        length = arg.length
        while ++index < length
          result = coercedSources[index](name)
          if result?
            return result
        return null
    else if 'string' is typeof arg
      hinoki.source hinoki.requireSource arg
    else if 'object' is typeof arg
      (name) ->
        arg[name]
    else
      throw new Error 'argument must be a function, string, object or array of these'

################################################################################
# return the hinoki object from the factory

  return hinoki
)
