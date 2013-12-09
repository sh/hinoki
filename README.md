# hinoki

[![Build Status](https://travis-ci.org/snd/hinoki.png)](https://travis-ci.org/snd/hinoki)

**magical inversion of control for nodejs**

hinoki can manage complexity in nodejs applications.

it is inspired by [prismatic's graph](https://github.com/Prismatic/plumbing#graph-the-functional-swiss-army-knife) and [angular's dependency injection](http://docs.angularjs.org/guide/di).

## get started

### install

```
npm install hinoki
```

**or**

put this line in the dependencies section of your `package.json`:

```
"hinoki": "0.3.0"
```

then run:

```
npm install
```

### require

```javascript
var hinoki = require('hinoki');
```

### let's make a graph

```javascript
var graph = {
    a: function() {
        return 1;
    },
    b: function(a) {
        return a + 1;
    },
    c: function(a, b) {
        return a + b;
    }
};
```

`a`, `b` and `c` are the **nodes** of the graph.

every node has a **factory** function:
node `a` has the factory `function() {return 1;}`.

the arguments of a factory are the **dependencies** of the node:
- `a` has no dependencies.
- `b` depends on `a`.
- `c` depends on `a` and `b`.

a factory returns the **instance** of a node.
it must be called with the instances of its dependencies:
`function(a) {return a + 1;}` must be called with the instance of `a`.

### let's make a container

we need a place to put those instances:
let's call it `instances`.

the pair of `factories` and `instances` is called a **container**. let's make one:

```javascript
var container = {
    factories: graph,
    instances: {}
};
```

if you omit the `instances` property hinoki will create one for you.

### let's ask for an instance

```javascript
hinoki.inject(container, function(c) {
    console.log(c); // => 3
});
```

the second argument to inject is a factory function.

because we asked for `c`, which depends on `a` and `b`, hinoki has
made instances for `a` and `b` as well and added them to the `instances` property:

```javascript
console.log(container.instances.a); // => 1
console.log(container.instances.b); // => 2
console.log(container.instances.c); // => 3
```

**hinoki will add every instance to the instances property.**

while `a` is a dependency of both `b` and `c`, the factory for `a` was only
called once. the second time `a` was needed it already had an instance.

**hinoki will only call the factory for nodes that have no instance.**

**hinoki will only call the factory for nodes that you ask for (or that the nodes you ask for depend on).**

let's provide an instance directly:

```javascript
var container = {
    factories: graph,
    instances: {
        a: 3
    }
};

hinoki.inject(container, function(a, b) {
    console.log(a) // => 3
    console.log(b) // => 4
});
```

the factory for `a` wasn't called since we already provided an instance for `a`.

we only asked for `a` and `b`. it was not necessary to get the instance for `c`:

```javascript
console.log(container.instances.a) // => 1
console.log(container.instances.b) // => 2
console.log(container.instances.c) // => undefined
```

##### programmatic usage

```javascript
var graph = {
    a: function() {
        return 1;
    },
    b: ['a', function(dep1) {
        return dep1 + 1;
    }],
    c: ['a', 'b', function(dep1, dep2) {
        return dep1 + dep2;
    }]
};
```

this is convenient.

hinoki parses dependencies from the function you pass to inject:

```javascript
hinoki.inject(container, 'a', function(dep1) {
    console.log(dep1) // => 1
    console.log(container.instances.a) // => 1
});
```

if a factory has a `$inject` property:

```javascript
var factory = function(dep1, dep2) {
    console.log(dep1) // => 1
    console.log(container.instances.a) // => 1

    console.log(dep2) // => 2
    console.log(container.instances.b) // => 2
};

factory['$inject'] = ['a', 'b'];

hinoki.inject(container, factory);
```

third style: array of dependency names followed by the factory

```javascript
hinoki.inject(container, ['a', 'b', function(dep1, dep2) {
    console.log(dep1) // => 1
    console.log(container.instances.a) // => 1

    console.log(dep2) // => 2
    console.log(container.instances.b) // => 2
}]);
```


### promises

if a factory returns a [q promise](https://github.com/kriskowal/q)
hinoki will wait until the promise is resolved.

this can greatly simplify complex async flows.

see [example/async.js](example/async.js).

### errors

promises

hinoki needs a way to communicate those problems

because

hinoki uses event emitters to accomplish this.

errors are emitted as the error event
nodejs throws those

```javascript
var EventEmitter = require('events').EventEmitter;

var emitter = new EventEmitter;

emitter.on('error', function() {

});

var container = {
    emitter: emitter
}
```

### debugging

to see what's going on

```javascript

emitter.on('instanceCreated', function() {

});

emitter.on('instanceFound', function() {

});

emitter.on('promiseCreated', function() {

});

emitter.on('promiseResolved', function() {

});
```

in addition to the errors the event

provide your own emitter (or any object that implements the
`emit` method)

## great! can i do anything useful with it?

### you can automate dependency injection

see [example/dependency-injection](example/dependency-injection):

[example/dependency-injection/load-sync.js](example/dependency-injection/load-sync.js)
is used by [example/dependency-injection/inject.js](example/dependency-injection/inject.js)
to pull in all the properties of the exports in the files in
[example/dependency-injection/factory](example/dependency-injection/factory).
hinoki then uses the graph of all those properties.
this enables inversion of control for all files in
[example/dependency-injection/factory](example/dependency-injection/factory).

**expect more documentation on this soon!**

### you can tame async flows

see [example/async.js](example/async.js)

### you can structure computation

see [example/computation.js](example/computation.js)

### license: MIT
