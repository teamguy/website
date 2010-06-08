sys: require 'sys'
require '../public/javascripts/underscore'
MongoDB: require('../lib/node-mongodb-native/lib/mongodb/db').Db
MongoServer: require('../lib/node-mongodb-native/lib/mongodb/connection').Server

class Mongo
  constructor: ->
    @server: new MongoServer 'localhost', 27017
    @db: new MongoDB 'nodeko', @server
    @db.open -> # no callback
exports.Mongo: Mongo

_.extend Mongo, {
  db: (new Mongo()).db

  bless: (klass) ->
    Serializer.bless klass
    _.extend klass.prototype, Mongo.InstanceMethods
    _.extend klass, Mongo.ClassMethods
    klass

  InstanceMethods: {
    collection: (fn) ->
      Mongo.db.collection @serializer.name, fn

    save: (fn) ->
      @collection (error, collection) =>
        return fn error if error?
        serialized: Serializer.pack this
        collection.insert serialized, fn
  }

  ClassMethods: {
    all: (fn) ->
      @prototype.collection (error, collection) ->
        return fn error if error?
        collection.find (error, cursor) ->
          return fn error if error?
          cursor.toArray (error, array) ->
            return fn error if error?
            fn null, Serializer.unpack array
  }
}

class Serializer
  constructor: (klass, name, options) ->
    [@klass, @name]: [klass, name]

    @allowNesting: options?.allowNesting
    @allowed: {}
    for i in _.compact _.flatten [options?.exclude]
      @allowed[i]: false

    # constructorless copy of the class
    @copy: -> # empty constructor
    @copy.prototype: @klass.prototype # same prototype

  shouldSerialize: (name, value) ->
    return false unless value?
    @allowed[name] ?= _.isString(value) or
      _.isNumber(value) or
      _.isBoolean(value) or
      _.isArray(value) or
      value.serializer?.allowNesting

  pack: (instance) ->
    packed: { serializer: @name }
    for k, v of instance when @shouldSerialize(k, v)
      packed[k]: Serializer.pack v
    packed

  unpack: (data) ->
    unpacked: new @copy()
    for k, v of data when k isnt 'serializer'
      unpacked[k]: Serializer.unpack v
    unpacked

_.extend Serializer, {
  instances: {}

  pack: (data) ->
    if s: data?.serializer
      s.pack data
    else if _.isArray(data)
      Serializer.pack i for i in data
    else
      data

  unpack: (data) ->
    if s: Serializer.instances[data?.serializer]
      s.unpack data
    else if _.isArray(data)
      Serializer.unpack i for i in data
    else
      data

  bless: (klass) ->
    [name, options]: _.flatten [ klass::serialize ]
    klass::serializer: new Serializer(klass, name, options)
    Serializer.instances[name]: klass::serializer

  blessAll: (namespace) ->
    for k, v of namespace when v::serialize?
      Serializer.bless v
}