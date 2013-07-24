q = require 'q'

module.exports =

    parseFunctionArguments: (fun) ->
        unless 'function' is typeof fun
            throw new Error 'argument must be a function'

        string = fun.toString()

        argumentPart = string.slice(string.indexOf('(') + 1, string.indexOf(')'))

        dependencies = argumentPart.split(/,\s/)

        return if dependencies[0] is '' then [] else dependencies

    inject: (container, fun) ->
        unless container.scope?
            container.scope = {}

        ids = module.exports.parseFunctionArguments fun

        module.exports.resolve container, ids, [], ->
            fun.apply null, arguments

    resolve: (container, ids, chain, cb) ->
        hasErrorOccured = false
        toBeResolved = 0

        maybeDone = ->
            if hasErrorOccured
                return
            if toBeResolved is 0
                dependencies = ids.map (id) -> container.scope[id]
                cb.apply null, dependencies

        ids.forEach (id) ->
            unless container.scope[id]?
                newChain = chain.concat([id])

                if id in chain
                    throw new Error "circular dependency #{newChain.join(' <- ')}"

                factory = container.factories?[id]
                unless factory?
                    throw new Error "missing factory for service '#{id}'"
                unless 'function' is typeof factory
                    throw new Error "factory is not a function '#{id}'"

                factoryIds = module.exports.parseFunctionArguments factory

                toBeResolved++
                module.exports.resolve container, factoryIds, newChain, ->
                    try
                        instance = factory.apply null, arguments
                    catch err
                        throw new Error "exception in factory '#{id}': #{err}"
                    unless q.isPromise instance
                        container.scope[id] = instance
                        toBeResolved--
                        return

                    onSuccess = (value) ->
                        container.scope[id] = value
                        toBeResolved--
                        maybeDone()
                    onError = (err) ->
                        hasErrorOccured = true
                        throw new Error "error resolving promise returned from factory '#{id}'"
                    instance.then onSuccess, onError

        maybeDone()
