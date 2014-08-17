Promise = require 'bluebird'
util = require 'util'

hinoki = require '../src/hinoki'

module.exports =

  'get value': (test) ->
    c =
      values:
        x: 1

    hinoki.get(c, 'x').then (x) ->
      test.equal x, 1
      test.equal c.values.x, 1
      test.done()

  'get null value': (test) ->
    c =
      values:
        x: null

    hinoki.get(c, 'x').then (x) ->
      test.ok hinoki.isNull x
      test.done()

  'sync get from factory': (test) ->
    c =
      factories:
        x: -> 1

    hinoki.get(c, 'x').then (x) ->
      test.equal x, 1
      test.equal c.values.x, 1
      test.done()

  'sync get null from factory': (test) ->
    c =
      factories:
        x: -> null

    hinoki.get(c, 'x').then (x) ->
      test.ok hinoki.isNull x
      test.ok hinoki.isNull c.values.x
      test.done()

  'async get from factory': (test) ->
    c =
      factories:
        x: -> Promise.resolve 1

    hinoki.get(c, 'x').then (x) ->
      test.equal x, 1
      test.equal c.values.x, 1
      test.done()

  'async get null from factory': (test) ->
    c =
      factories:
        x: -> Promise.resolve null

    hinoki.get(c, 'x').then (x) ->
      test.ok hinoki.isNull x
      test.ok hinoki.isNull c.values.x
      test.done()

  'sync get with dependencies': (test) ->
    c =
      factories:
        x: (y) -> 1 + y
        y: -> 1

    hinoki.get(c, 'x').then (x) ->
      test.equal x, 2
      test.done()

  'sync get null with dependencies': (test) ->
    c =
      factories:
        x: (y) -> null
        y: -> 1

    hinoki.get(c, 'x').then (x) ->
      test.ok hinoki.isNull x
      test.ok hinoki.isNull c.values.x
      test.done()

  'containers are tried in order. values are created in container that resolved factory': (test) ->
    c1 =
      factories:
        a: (b) ->
          b + 1

    c2 =
      factories:
        b: (c) ->
          c + 1

    c3 =
      factories:
        c: (d) ->
          d + 1
        d: ->
          1

    hinoki.get([c1, c2, c3], ['a', 'd']).spread (a, d) ->
      test.equal a, 4
      test.equal d, 1

      test.equal c1.values.a, 4
      test.equal c2.values.b, 3
      test.equal c3.values.c, 2
      test.equal c3.values.d, 1

      test.done()

  'containers can not depend on previous containers': (test) ->
    c1 =
      factories:
        a: ->
          1

    c2 =
      factories:
        b: (a) ->
          a + 1

    hinoki.get([c1, c2], 'b').catch (error) ->
      test.equal error.type, 'UnresolvableFactoryError'
      test.deepEqual error.path, ['a', 'b']
      test.done()

  'a factory is called no more than once': (test) ->
    callsTo =
      a: 0
      b: 0
      c: 0
      d: 0

    c =
      factories:
        a: (b, c) ->
          test.ok callsTo.a < 2
          Promise.delay(b + c, 40)
        b: (d) ->
          test.ok callsTo.b < 2
          Promise.delay(d + 1, 20)
        c: (d) ->
          test.ok callsTo.c < 2
          Promise.delay(d + 2, 30)
        d: ->
          test.ok callsTo.d < 2
          Promise.delay(10, 10)

    hinoki.get(c, 'a').then (a) ->
      test.equal a, 23
      test.done()

  'resolvers wrap around default resolver': (test) ->
    a = {}
    b = {}

    c =
      factories:
        a: -> a

    c2 =
      factories:
        b: -> b

    c.resolvers = [
      (query, inner) ->
        test.equal query.container, c
        test.deepEqual query.path, ['a']
        inner
          container: c2
          path: ['b']
    ]

    hinoki.get(c, 'a').then (value) ->
      test.equal b, value
      test.equal c2.values.b, value
      test.done()

  'resolvers wrap around inner resolvers': (test) ->
    c = {}
    c2 = {}
    c3 = {}

    value = {}

    c.resolvers = [
      (query, inner) ->
        test.deepEqual query,
          container: c
          path: ['a']
        inner
          container: c2
          path: ['b']
      (query) ->
        test.deepEqual query,
          container: c2
          path: ['b']
        {
          factory: ->
            value
          container: c3
          path: ['c']
        }
    ]

    hinoki.get(c, 'a').then (a) ->
      test.equal a, value
      test.equal c3.values.c, value
      test.done()

  'a resolver can disable caching': (test) ->
    c = {}

    value = {}

    c.resolvers = [
      (query, inner) ->
        test.deepEqual query,
          container: c
          path: ['a']
        return {
          nocache: true
          container: c
          factory: ->
            value
        }
    ]

    hinoki.get(c, 'a').then (a) ->
      test.equal a, value
      test.ok not c.values?
      test.done()

  'a factory with $nocache property is not cached': (test) ->
    c =
      factories:
        x: -> 1

    c.factories.x.$nocache = true

    hinoki.get(c, 'x').then (x) ->
      test.equal x, 1
      test.ok not c.values?
      test.done()

  'mocking a factory for any require': (test) ->
    test.expect 5
    resolver = (query, inner) ->
      if query.path[0] is 'bravo'
        {
          container: query.container
          path: query.path
          factory: (charlie) ->
            charlie.split('').reverse().join('')
          nocache: true
        }
      else
        inner query
    container =
      factories:
        alpha: -> 'alpha'
        bravo: -> 'bravo'
        charlie: -> 'charlie'
        alpha_bravo: (alpha, bravo) ->
          alpha + '_' + bravo
        bravo_charlie: (bravo, charlie) ->
          bravo + '_' + charlie
        alpha_charlie: (alpha, charlie) ->
          alpha + '_' + charlie
      resolvers: [resolver]

    hinoki.get(container, ['alpha_bravo', 'bravo_charlie', 'alpha_charlie'])
      .spread (alpha_bravo, bravo_charlie, alpha_charlie) ->
        test.equal alpha_bravo, 'alpha_eilrahc'
        test.equal bravo_charlie, 'eilrahc_charlie'
        test.equal alpha_charlie, 'alpha_charlie'
        # note that bravo is not cached
        test.deepEqual container.values,
          alpha: 'alpha',
          charlie: 'charlie',
          alpha_charlie: 'alpha_charlie',
          bravo_charlie: 'eilrahc_charlie',
          alpha_bravo: 'alpha_eilrahc'
        test.equal 0, Object.keys(container.underConstruction)
        test.done()

  'mocking a factory for requires from a specific other factory': (test) ->
    test.expect 5
    resolver = (query, inner) ->
      if query.path[0] is 'bravo' and query.path[1] is 'bravo_charlie'
        # only mock out when required by bravo_charlie
        {
          container: query.container
          path: query.path
          factory: (charlie) ->
            charlie.split('').reverse().join('')
          nocache: true
        }
      else
        inner query
    container =
      factories:
        alpha: -> 'alpha'
        bravo: -> 'bravo'
        charlie: -> 'charlie'
        alpha_bravo: (alpha, bravo) ->
          alpha + '_' + bravo
        bravo_charlie: (bravo, charlie) ->
          bravo + '_' + charlie
        alpha_charlie: (alpha, charlie) ->
          alpha + '_' + charlie
      resolvers: [resolver]

    hinoki.get(
      container
      ['alpha_bravo', 'bravo_charlie', 'alpha_charlie']
    )
      .spread (alpha_bravo, bravo_charlie, alpha_charlie) ->
        test.equal alpha_bravo, 'alpha_bravo'
        test.equal bravo_charlie, 'eilrahc_charlie'
        test.equal alpha_charlie, 'alpha_charlie'
        # bravo is cached for all cases but the ones where
        # bravo_charlie requires it
        test.deepEqual container.values,
          alpha: 'alpha',
          charlie: 'charlie',
          bravo: 'bravo'
          alpha_charlie: 'alpha_charlie',
          bravo_charlie: 'eilrahc_charlie',
          alpha_bravo: 'alpha_bravo'
        test.equal 0, Object.keys(container.underConstruction)
        test.done()

# TODO this should be possible but is not possible with the way
# hinoki currently works

#   'mocking a factory for all requires that originate in some way from a specific factory': (test) ->
#     # test.expect 8
#     resolver = (query, inner) ->
#       # we are mocking out just 'bravo' under the circumstance that
#       # it is required somehow by 'bravo_bravo_charlie'.
#       # in other words that 'bravo_bravo_charlie' is somewhere upstream.
#       # this means if 'bravo' is required by 'bravo_charlie' directly
#       # it should resolve per default.
#       # if 'bravo' is required by 'bravo_charlie' and 'bravo_charlie' is requred
#       # by 'bravo_bravo_charlie' then it should be mocked.
#
#       # what happens is:
#       # 1. alpha_bravo is required, no mock, bravo is cached
#       # 2. bravo_charlie is required, mo mock, bravo_charlie is cached
#
#       # bravo_charlie is required by bravo_bravo_charlie
#       # but the resolver is not run because it is already cached?
#
#       # bravo charlie is required at toplevel before bravo_bravo_charlie
#       # bravo is required by bravo_charlie
#       # here bravo_bravo_charlie is not in path
#       # and bravo as well as bravo_charlie are cached
#       #
#       # bravo_bravo_charlie now requires bravo_charlie directory
#       # bravo_charlie on its own doesnt trigger the resolver !
#       # it is returned in its cached form
#
#       # the problem is that we wont even get to the point where we
#       # see that bravo_charlie requires bravo as it is already cached
#       #
#       # maybe look up in the injects of the factory as well?
#       #
#       #
#       # the main problem is that alpha_bravo should not be cached
#       # because it depends on bravo.
#       # but its impossible for a resolver to know that alpha_bravo
#       # depends on bravo.
#
#       console.log query.path
#       if 'bravo' in query.path
#       # if 'bravo' is query.path[0]
#         if 'bravo' is query.path[0] and 'bravo_bravo_charlie' in query.path
#         # if 'bravo_bravo_charlie' in query.path
#           # only mock out when bravo_charlie is somewhere upstream
#           {
#             container: query.container
#             path: query.path
#             factory: (charlie) ->
#               charlie.split('').reverse().join('')
#             nocache: true
#           }
#         else
#           # disable caching for everything that uses bravo
#           result = inner query
#           result.nocache = true
#           result
#       else
#         inner query
#     container =
#       factories:
#         alpha: -> 'alpha'
#         bravo: -> 'bravo'
#         charlie: -> 'charlie'
#         alpha_bravo: (alpha, bravo) ->
#           alpha + '_' + bravo
#         bravo_charlie: (bravo, charlie) ->
#           bravo + '_' + charlie
#         alpha_charlie: (alpha, charlie) ->
#           alpha + '_' + charlie
#         # all bravos upstream are mocked
#         bravo_bravo_charlie: (bravo, bravo_charlie) ->
#           bravo + '_' + bravo_charlie
#         alpha_bravo_charlie: (alpha_bravo, charlie) ->
#           alpha_bravo + '_' + charlie
#         # just bravos upstream of bravo_bravo_charlie are mocked
#         alpha_bravo_bravo_bravo_charlie: (alpha_bravo, bravo_bravo_charlie) ->
#           alpha_bravo + '_' + bravo_bravo_charlie
#       resolvers: [resolver]
#
#     hinoki.get(
#       container
#       [
#         'alpha_bravo'
#         'bravo_charlie'
#         'alpha_charlie'
#         'bravo_bravo_charlie'
#         'alpha_bravo_charlie'
#         'alpha_bravo_bravo_bravo_charlie'
#       ]
#     )
#       .spread (alpha_bravo, bravo_charlie, alpha_charlie, bravo_bravo_charlie, alpha_bravo_charlie, alpha_bravo_bravo_bravo_charlie) ->
#         console.log container.values
#         test.equal alpha_bravo, 'alpha_bravo'
#         test.equal bravo_charlie, 'bravo_charlie'
#         test.equal alpha_charlie, 'alpha_charlie'
#         test.equal bravo_bravo_charlie, 'eilrahc_eilrahc_charlie'
#         test.equal alpha_bravo_charlie, 'alpha_bravo_charlie'
#         # test.equal alpha_bravo_bravo_bravo_charlie, 'alpha_bravo_eilrahc_eilrahc_charlie'
#         # test.deepEqual container.values,
#         #   alpha: 'alpha',
#         #   charlie: 'charlie',
#         #   bravo: 'bravo'
#         #   alpha_bravo: 'alpha_bravo'
#         #   bravo_charlie: 'bravo_charlie'
#         #   alpha_charlie: 'alpha_charlie'
#         #   bravo_bravo_charlie: 'eilrahc_eilrahc_charlie'
#         #   alpha_bravo_charlie: 'alpha_bravo_charlie'
#         test.equal 0, Object.keys(container.underConstruction)
#         test.done()
