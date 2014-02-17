# hinoki

[![Build Status](https://travis-ci.org/snd/hinoki.png)](https://travis-ci.org/snd/hinoki)

**magical inversion of control for nodejs**

hinoki can manage complexity in nodejs applications.

it is inspired by [prismatic's graph](https://github.com/Prismatic/plumbing#graph-the-functional-swiss-army-knife) and [angular's dependency injection](http://docs.angularjs.org/guide/di).

*Hinoki takes its name from the hinoki cypress, a tree that only grows in Japan and is the preferred wood for building palaces, temples and shrines.*

### install

```
npm install hinoki
```

**or**

put this line in the dependencies section of your `package.json`:

```
"hinoki": "0.3.0-beta.3"
```

then run:

```
npm install
```

# the documentation below is work in progress!

- [events](#events)

If a factory returns a thenable (bluebird or q promise) it will 

### container

the central data structure used in hinoki is a container.

a container is an object with the following properties:

#### factories

an object

#### instances

an object

#### 

#### underConstruction

#### emitter

see [events](#events) for more.

the container is a stateful object

### events

a container has an `emitter` property.
if no `emitter` property is set one is created
as soon as the first event would be emitted using `new require('events').EventEmitter()`.

errors are emitted as the `error` event.
`error` events are treated as a special case in node.
if there is no listener for it, then the default action is to print a stack
trace and exit the program.



#### instanceFound

emitted whenever an instance is requested and already found in the
`instances` property of a container

```javascript
{
    event: 'instanceFound'
    id: /* array of strings */,
    value: /* the instance that was created */,
    container: /* container */
}
```

#### instanceCreated

emitted whenever an instance is requested, was not found, the factory was called
returns an instance that is not a [thenable](http://promises-aplus.github.io/promises-spec/).

payload:

```javascript
{
    event: 'instanceCreated'
    id: /* array of strings */,
    value: /* the instance that was created */,
    container: /* container */
}
```

#### promiseCreated

#### promiseResolved



#### error

all errors are emitted as the `error` event.

##### cycle

##### missingFactory

##### exception

##### promiseRejected

##### factoryNotFunction

##### factoryReturnedUndefined

- `any` to listen 

### license: MIT
