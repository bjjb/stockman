"use strict"

VERSION = 1
GOOGLE =
  api_key: "AIzaSyDY9L74caWHWKwQt3v8PhUKJg1XrV1Sg1M"
  script_id: 'MCYPtGyMDBqYLtIXwqu-mpGxMYCeUYLF8'
  scripts_uri: "https://script.googleapis.com/v1/scripts"
  client_id: "882209763081-kkne3l1sio3iro2u0ddt0mi5m9c6lf61.apps.googleusercontent.com"
  client_secret: "0og9Da5QRapxyv8MvYCAOSkD"
  auth_uri: "https://accounts.google.com/o/oauth2/auth"
  token_uri: "https://www.googleapis.com/oauth2/v3/token"
  scopes: [
    'https://www.googleapis.com/auth/spreadsheets'
    'https://www.googleapis.com/auth/drive'
  ]
SYNC_INTERVAL = 1000 * 60 * 60 # 1 hour

# Little AJAX library
ajax =
  handle: (handlers = {}) -> (e) -> handlers[@status]?(e)
  request: ({ method, url, headers, data, handlers }) ->
    headers ?= {}
    handlers ?= {}
    data = utils.urlencode(data) if typeof data is 'object'
    new Promise (resolve, reject) ->
      xhr = new XMLHttpRequest
      xhr.open(method, url)
      xhr.setRequestHeader(k, v) for own k, v of headers
      xhr.addEventListener(k, v) for own k, v of handlers
      xhr.send(data)

rejolve = (x) -> Promise[x? and 'resolve' or 'reject'](x)
urlencode = (o) -> ([k, v].map(encodeURIComponent).join('=') for own k, v of o).join('&')
taskChain = (tasks) -> tasks.reduce ((p, t) -> p.then(t)), Promise.resolve()
arrayify = (obj) -> x for x in obj # !!arrayify(arguments) instanceof Array //=> true
serializeXML = (xml) -> xml.documentElement.innerHTML
deserializeXML = (s,t) -> x = document.createElement(t ? 'feed'); x.innerHTML = s; x
apply = (f) -> (a...) -> (o) -> o[f](a...) # apply('toLowerCase')()("BOO!") //=> "boo!" 
putProperty = (o) -> (k) -> (x) -> o[k] = x
getProperty = (o) -> (k) -> if o[k]? then Promise.resolve(o[k]) else Promise.reject(putProperty(o)(k))
utils = { rejolve, urlencode, ajax, taskChain, arrayify, serializeXML, deserializeXML, getProperty, putProperty }


Order = (@data) ->
OrderItem = (@data) ->
Product = (@data) ->
  
UI = ({ document, location, Promise, Mustache, setTimeout, console, sync, authorize }) ->
  # DOM manipulation utilities
  $       = (q) => document.querySelector(q)
  $$      = (q) => e for e in document.querySelectorAll(q)
  goto    = (q) => [lastLocation, location.hash] = [location.hash, q]
  show    = (qs...) -> (e.hidden = false for e in $$(q)) for q in qs
  hide    = (qs...) -> (e.hidden = true for e in $$(q)) for q in qs
  enable  = (qs...) -> (e.disabled = false for e in $$(q)) for q in qs
  disable = (qs...) -> (e.disabled = true for e in $$(q)) for q in qs
  addClass = (qs...) -> (classes...) -> ((e.classList.add(c) for c in classes) for e in $$(q)) for q in qs
  removeClass = (qs...) -> (classes...) -> ((e.classList.remove(c) for c in classes) for e in $$(q)) for q in qs
  replaceClass = (qs...) ->
    (remove...) ->
      (add...) ->
        (removeClass(q)(c) for c in remove) for q in qs
        (addClass(q)(c) for c in add) for q in qs
  render = (qs...) ->
    partials = (k) -> $(k).innerHTML or throw "Partial template missing: #{k}"
    (view) ->
      for q in qs
        for e in $$(q)
          return console.error("No template", e) unless t = e.dataset.template
          return console.error("Template missing", t) unless t = $(t)?.innerHTML
          console.debug "Rendering", view
          e.innerHTML = Mustache.render(t, view, partials)
      view
  listen = (qs...) ->
    (event) ->
      (callback) ->
        for q in qs
          e.removeEventListener(event, callback) for e in $$(q)
          e.addEventListener(event, callback)    for e in $$(q)
  ignore = (qs...) ->
    (event) ->
      (callback) ->
        for q in qs
          e.removeEventListener(event, callback) for e in $$(q)
  # Specific DOM wrapper functions
  fatal = (error) -> # Show a fatal message
    $('.fatal.alert .message').innerHTML = error.message
    show('.fatal.alert')
  sync = (f) -> # Show sync status
    success = ({ orders, inventory }) ->
      replaceClass('.synchronizing')('working')('success')
      setTimeout((-> hide('.synchronizing')), 5000)
      { orders, inventory }
    error = (error) ->
      replaceClass('.synchronizing')('working')('error')
      throw error
    replaceClass('.synchronizing')('success', 'error')('working')
    show('.synchronizing')
    f().then(success, error)
  chooseSpreadsheet = (getView) ->
    (callback) ->
      new Promise (resolve, reject) ->
        change = ->
          $('#choose-spreadsheet p').innerHTML = "Select this spreadsheet?"
          enable('#choose-spreadsheet select')
          enable('#choose-spreadsheet button')
        submit = ->
          $('#choose-spreadsheet p').innerHTML = ""
          disable('#choose-spreadsheet button')
          disable('#choose-spreadsheet select')
          callback(@spreadsheet.value)
        wait = ->
          hide('#choose-spreadsheet .spinner')
          enable('#choose-spreadsheet select')
          replaceClass('#choose-spreadsheet button')('btn-default')('btn-success')
        $('#choose-spreadsheet p').innerHTML = "Getting your spreadsheets..."
        addClass('#choose-spreadsheet')('fetching')
        listen('#choose-spreadsheet select')('change')(change)
        listen('#choose-spreadsheet form')('submit')(submit)
        goto('#choose-spreadsheet')
        getView().then(render('#choose-spreadsheet select')).then(wait)
  update = ({ orders, inventory }) ->
    render('#orders .panel-group.orders')({orders})
    render('#inventory tbody.products')({inventory})
    { orders, inventory }
  {$, $$, goto, show, hide, enable, disable, render, fatal, sync, authorize,
    update, chooseSpreadsheet }

Changes = ({ ui }) ->

# Interface for interacting with the spreadsheet over Google Apps Script.
Spreadsheet = ({ ui, auth, download, sync, run, spreadsheet }) ->
  { scripts_uri, script_id } = GOOGLE
  auth ?= ->
    oauth2rizer(GOOGLE)()
  spreadsheet ?= ->
    getProperty(localStorage)('spreadsheet').catch(ui.chooseSpreadsheet(spreadsheet.choose))
  spreadsheet.choose ?= ->
    run('SpreadsheetFiles')().then (spreadsheets) -> { spreadsheets }
  run ?= (functionName) ->
    url = "#{scripts_uri}/#{script_id}:run"
    data = { function: functionName, devMode: true }
    (parameters...) ->
      new Promise (resolve, reject) ->
        load = ->
          response = JSON.parse(@responseText)
          if response.error?
            console.error response.error
            reject response.error
          resolve response.response.result
        handlers = { load }
        data.parameters = parameters
        method = 'post'
        post = (token) ->
          method = 'post'
          headers = { Authorization: "Bearer #{token}" }
          data = JSON.stringify(data)
          ajax.request({ method, url, headers, data, handlers })
        auth().then(post)
  download ?= ->
    console.debug "Spreadsheet download", @
    spreadsheet()
      .then(run('AllSpreadsheetObjects'))
      .then ({ ORDERS, INVENTORY }) ->
        orders: (o for o in ORDERS when o.Product)
        inventory: (p for p in INVENTORY when p.Product)
  { run, download }

Database = ({ ui, name, version, error, result, results, upgradeneeded, open,
              transaction, objectStore, store, update } = {}) ->
  name    ?= 'stockman'
  version ?= 1
  error ?= (reject) ->
    (event) ->
      console.error "Database error: ", @, arguments
      reject(error)
  result ?= (resolve) ->
    (event) ->
      console.debug "Database result! ", @, arguments
      resolve(@result)
  results ?= (resolve, reject) ->
    results = []
    (event) ->
      console.debug "Database results! ", @, arguments
      return resolve(results) unless @result
      results.push(@result.value)
      @result.continue()
  upgradeneeded ?= (reject) ->
    (event) ->
      console.debug "Database migration...", @, arguments
      os = @result.createObjectStore 'inventory', keyPath: "ID", autoIncrement: true
      os.createIndex 'Product', 'Product', unique: false
      os = @result.createObjectStore 'orders', keyPath: "ID", autoIncrement: true
      os.createIndex 'Customer', 'Customer', unique: false
      os.createIndex 'Product', 'Product', unique: false
      os.createIndex 'Status', 'Status', unique: false
      console.debug "Database migration complete", @, arguments
  open = ->
    new Promise (resolve, reject) ->
      request = indexedDB.open(name)
      request.addEventListener 'error', error(reject)
      request.addEventListener 'success', result(resolve)
      request.addEventListener 'blocked', error(reject)
      request.addEventListener 'upgradeneeded', upgradeneeded(reject)
  transaction = (storeNames, mode) ->
    (db) ->
      new Promise (resolve, reject) ->
        resolve(db.transaction(storeNames, mode))
  objectStore = (storeName) ->
    (transaction) ->
      transaction.objectStore(storeName)
  store = (name) ->
    count = (key) ->
      new Promise (resolve, reject) ->
        db.then(transaction(name)).then(objectStore(name)).then (objectStore) ->
          request = objectStore.count(key)
          request.addEventListener 'success', result(resolve)
          request.addEventListener 'error', error(reject)
    get = (key) ->
      new Promise (resolve, reject) ->
        db.then(transaction(name)).then(objectStore(name)).then (objectStore) ->
          request = objectStore.get(key)
          request.addEventListener 'success', result(resolve)
          request.addEventListener 'error', error(reject)
    add = (object, key) ->
      console.debug "db add #{name}", object, key
      new Promise (resolve, reject) ->
        db.then(transaction(name, 'readwrite')).then(objectStore(name)).then (objectStore) ->
          request = objectStore.add(object, key)
          request.addEventListener 'success', result(resolve)
          request.addEventListener 'error', error(reject)
    put = (object, key) ->
      new Promise (resolve, reject) ->
        db.then(transaction(name, 'readwrite')).then(objectStore(name)).then (objectStore) ->
          request = objectStore.put(object, key)
          request.addEventListener 'success', result(resolve)
          request.addEventListener 'error', error(reject)
    delete_ = (key) ->
      new Promise (resolve, reject) ->
        success = -> resolve(@result)
        error = -> reject(@error)
        db.then(transaction(name, 'readwrite')).then(objectStore(name)).then (objectStore) ->
          request = objectStore.delete(object, key)
          request.addEventListener 'success', result(resolve)
          request.addEventListener 'error', error(reject)
    all = (range) ->
      new Promise (resolve, reject) ->
        db.then(transaction(name)).then(objectStore(name)).then (objectStore) ->
          request = objectStore.openCursor(range)
          request.addEventListener 'success', results(resolve)
          request.addEventListener 'error', error(reject)
    index = (name) ->
      db.then(transaction(name)).then(objectStore(name)).then (objectStore) ->
        objectStore.index(name)
    obj = { count, get, add, put, all, index }
    obj.delete = delete_
    obj
  update = ({ orders, inventory }) ->
    console.debug "UPDATING DATABASE...", orders, inventory
    { orders, inventory }
  orders = store('orders')
  orders.open = -> orders.index('Product').
  inventory = store('inventory')
  db = open(name, version)
  { orders, inventory, update }
  
Stockman = (event) ->
  f = ({ ui, backend, db, changes, sync, offline, online, start, fatal } = {}) ->
    ui        ?= UI(@)
    backend   ?= Spreadsheet({ ui })
    db        ?= Database({ ui })
    changes   ?= Changes({ ui })
    sync ?= ->
      ui.sync ->
        getData = new Promise (resolve, reject) ->
          { orders, inventory, lastSync } = localStorage
          if orders and inventory and lastSync > new Date().getTime() - SYNC_INTERVAL
            resolve # Load from cache, if within SYNC_INTERVAL
              orders: JSON.parse(orders)
              inventory: JSON.parse(inventory)
          else
            backend.download(lastSync).then ({ orders, inventory }) ->
              localStorage.orders = JSON.stringify(orders)
              localStorage.inventory = JSON.stringify(inventory)
              localStorage.lastSync = new Date().getTime()
              resolve { orders, inventory }
        getData.then(db.update)
    offline ?= ->
      ui.show('.alert.offline')
    online ?= ->
      ui.hide('.alert.offline')
      setTimeout (-> ui.hide('.alert.online')), 5000
    start ?= ->
      console.log "Welcome to Stockman v#{VERSION}"
      sync().then(ui.update)
    fatal ?= (error) ->
      ui.fatal(error.message)
      throw new Error(error)
    offline() unless @navigator.onLine
    @addEventListener 'online', online
    @addEventListener 'offline', offline
    @stockman = { ui, db, backend, changes, sync, orders, inventory, start }
    start()
  f.call(@)


Stockman.UI = UI
Stockman.Spreadsheet = Spreadsheet
Stockman.Changes = Changes
Stockman.Order = Order
Stockman.OrderItem = OrderItem
Stockman.Product = Product
Stockman.VERSION = VERSION
Stockman.utils = utils

addEventListener 'load', Stockman
@Stockman = Stockman
