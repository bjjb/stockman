'use strict'

# IndexTheBee - an IndexedDB wrapper
Database = (idb) ->
  self = @
  transaction = idb.transaction(idb.objectStoreNames)
  objectStoreNames = (n for n in idb.objectStoreNames)
  objectStoreNames.forEach (store) ->
    f = (mode = 'readonly') -> idb.transaction(store, mode).objectStore(store)
    ['count', 'get', 'getAll', 'openCursor', 'add', 'put', 'delete',
    'clear'].forEach (action) ->
      f[action] = Database[action](f)
    indexNames = (n for n in transaction.objectStore(store).indexNames)
    indexNames.forEach (index) ->
      g = -> f().index(index)
      ['count', 'get', 'getAll'].forEach (action) ->
        g[action] = Database[action](g)
      f[index] = g
    self[store] = f
  @idb = idb
  @

Database.read = (action) ->
  (target) ->
    (range, direction) ->
      new Promise (resolve, reject) ->
        args = []
        args.push(Database.keyRange(range)) if range?
        args.push(direction) if direction?
        result = []
        r = target()[action](args...)
        r.addEventListener 'success', ->
          return resolve(result) unless @result?
          return resolve(@result) unless @result.value?
          result.push(@result.value)
          @result.continue()
        r.addEventListener 'error', ->
          console.error @error
          reject @error.message

Database.write = (action) ->
  (target) ->
    (object, key) ->
      new Promise (resolve, reject) ->
        r = target('readwrite')[action](object, key)
        r.addEventListener 'success', ->
          console.debug "Overwrote", object, key
          resolve(@result)
        r.addEventListener 'error', ->
          console.error @error
          reject @error.message

Database.count = Database.read('count')
Database.get = Database.read('get')
Database.openCursor = Database.read('openCursor')
Database.getAll = Database.read('openCursor')
Database.add = Database.write('add', 'readwrite')
Database.put = Database.write('put', 'readwrite')
Database.delete = Database.write('delete', 'readwrite')
Database.clear = Database.write('clear', 'readwrite')

Database.keyRange = (arg) ->
  return IDBKeyRange.only(arg) unless arg instanceof Array
  [lower, upper] = arg
  if lower?
    if upper?
      IDBKeyRange.bound(lower, upper)
    else
      IDBKeyRange.lowerBound(lower)
  else
    IDBKeyRange.upperBound(upper)
