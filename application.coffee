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
apply = (f) -> (a...) -> (o) -> o[f](a...) # apply('toLowerCase')()("BOO!") //=> "boo!" 
putProperty = (o) -> (k) -> (x) -> o[k] = x
getProperty = (o) -> (k) -> if o[k]? then Promise.resolve(o[k]) else Promise.reject(putProperty(o)(k))

utils = { rejolve, urlencode, ajax, taskChain, arrayify, getProperty, putProperty }


OrderItem = (data) ->
  @[k] = v for own k, v of data when v isnt ''
  @[k] = new Date(@[k]) for k in ['updated', 'date_sold', 'hold_until'] when @[k]
  @
OrderItem::getOrderID = -> @order ? @customer
OrderItem::bsClass = ->
  switch @status
    when 'SOLD' then 'success'
    when 'OPEN' then 'info'
    when 'HOLD' then 'warning'
    when 'SHORT' then 'success'
Product = (data) ->
  @[k] = v for own k, v of data when v isnt ''
  @[k] = new Date(@[k]) for k in ['updated'] when @[k]
  @
Order = ({ @customer, @id }) ->
  @orderItems = []
  @
Order::price = ->
  p = 0
  p + (i.price ? 0) for i in @orderItems when i.status is 'SOLD'
  p.toFixed(2)
Order::status = ->
  return 'CLOSED' if @orderItems.every (i) -> i.status in ['SOLD']
  'OPEN'
Order::bsClass = ->
  switch @status()
    when 'OPEN' then 'panel-info'
    when 'CLOSED' then 'panel-default'
  
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
          console.debug('UI#render', qs, e, view)
          return console.error("No template", e) unless t = e.dataset.template
          return console.error("Template missing", t) unless t = $(t)?.innerHTML
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
  update = ({ orders, inventory }) ->
    render('#orders .panel-group.orders')({orders})
    render('#inventory tbody.products')({inventory})
    { orders, inventory }
  {$, $$, goto, show, hide, enable, disable, render, update, addClass,
    removeClass, replaceClass, listen, ignore }

Changes = ({ ui }) ->

ui = null # A collection of helpers for modifying the DOM

# A promise that resolves when the window is loaded
getUI = new Promise (resolve, reject) ->
  window.addEventListener 'load', ->
    resolve(ui = UI(@))

# Starts the whole thing
started = false
start = ->
  Promise.resolve()
    .then synchronize
    .then renderInventory
    .then renderOrders
    .then -> ui.goto('#dashboard') unless location.hash?
    .then -> started = true

# Synchronize the local database with the spreadsheet
synchronize = ->
  Promise.resolve()
    .then showSynchronizing
    .then getSpreadsheetChanges
    .then getChanges
    .then updateSpreadsheet
    .then showSynchronizationSuccess
    .catch showSynchronizationFailure

# Render the inventory section
renderInventory = ->
  console.debug "renderInventory..."
  getUI
    .then getInventory
    .then (products) -> ui.render('#inventory tbody.products')({products})

# Render the orders section
renderOrders = ->
  getUI
    .then -> getOrders()
    .then (orders) -> ui.render('#orders div.orders')({orders})

# Gets the inventory from the database
getInventory = ->
  getAll('inventory')().then (products) ->
    new Product(p) for p in products

# Gets the orders from the database, and makes Orders objects
getOrders = ->
  getAll('orders')().then (orderItems) ->
    orderItems = (new OrderItem(o) for o in orderItems)
    orders = {}
    for orderItem, id in orderItems
      order_id = orderItem.getOrderID()
      { customer } = orderItem
      order = orders[order_id] ?= new Order({ customer, id })
      order.orderItems.push(orderItem)
    (v for own k, v of orders)

# Gets a function to merge the second argument into the first
merge = (first) ->
  (second) ->
    first[k] = v for own k, v of second
    first

getChanges = ->
  console.debug "Getting changes..."

# Converts a list of changes into arguments that can be passed along to the
# Apps Script.
formatDatabaseChanges = (changes) ->
  changeToScriptParams(change) for change in changes

# Gets all the objects in a store
getAll = (store) ->
  ->
    new Promise (resolve, reject) ->
      openDB.then ->
        results = []
        request = db.transaction(store).objectStore(store).openCursor()
        request.addEventListener 'error', (e) -> throw Error(e)
        request.addEventListener 'success', ->
          return resolve(results) unless @result?
          results.push(@result.value)
          @result.continue()

getAllBy = (store) ->
  (index) ->
    new Promise (resolve, reject) ->
      openDB.then ->
        results = []
        request = db.transaction(store).objectStore(store).index(index).openCursor()
        request.addEventListener 'error', (e) -> throw Error(e)
        request.addEventListener 'success', ->
          return resolve(results) unless @result?
          results.push(@result.value)
          @result.continue()

# Updates the spreadsheet with the values supplied
# Expects an object like:
#    { sheet: changes }
# where sheet is the Sheet name and changes is an array of Change objects.
# where the key is the spreadsheet name, the first sub-array is a list of
updateSpreadsheet = (changes) ->
  console.debug "Syncing changes to DB", changes
  

# Show that some synchronization is happening
showSynchronizing = ->
  getUI.then ->
    ui.replaceClass('.synchronizing')('success', 'error')('working')
    ui.show('.synchronizing')
    console.debug("Synchronizing...")

# Show that the synchronizing has finished
showSynchronizationSuccess = ->
  getUI.then ->
    ui.replaceClass('.synchronizing')('working')('success')
    setTimeout((-> ui.hide('.synchronizing')), 3000)

# Show that the synchronizing has failed
showSynchronizationFailure = (reason) ->
  getUI.then ->
    console.error reason
    ui.replaceClass('.synchronizing')('working')('error')
    ui.$('.synchronizing .reason').innerHTML = reason
    setTimeout((-> ui.hide('.synchronizing')), 5000)

# Gets the time the app and the spreadsheet were last synced.
getLastSyncedTime = ->
  { lastSynced } = localStorage
  new Date(lastSynced) if lastSynced?

# Gets the ID of the spreadsheet - tries to get it from localStorage, shows
# the chooser otherwise.
getSpreadsheetID = ->
  new Promise (resolve, reject) ->
    { spreadsheet_id } = localStorage
    return resolve(spreadsheet_id) if spreadsheet_id
    chooseSpreadsheet()
    reject("You need to choose a spreadsheet.")

# Shows the spreadsheet chooser
chooseSpreadsheet = ->
  getUI.then ->
    ui.goto('#choose-spreadsheet')
    ui.addClass('#choose-spreadsheet')('fetching')
    getUserSpreadsheets().then (spreadsheets) ->
      ui.render('#choose-spreadsheet select')({spreadsheets})
      ui.enable('#choose-spreadsheet select')
      ui.replaceClass('#choose-spreadsheet')('fetching')('waiting')
      ui.listen('#choose-spreadsheet select')('change') ->
        ui.enable('#choose-spreadsheet button')
        ui.listen('#choose-spreadsheet form')('submit') (event) ->
          event.preventDefault()
          localStorage.spreadsheet_id = @spreadsheet.value
          start()

# Caches the result of f as key in storage.
cache = (storage) ->
  (key) ->
    (f) ->
      return Promise.resolve(JSON.parse(storage.getItem(key))) if storage.hasOwnProperty(key)
      f().then (result) ->
        storage.setItem(key, JSON.stringify(result)) if DEBUG?
        result

# Gets a list of spreadsheets in the user's Google Drive
getUserSpreadsheets = ->
  cache(sessionStorage)('spreadsheets') ->
    executeAppsScriptFunction('SpreadsheetFiles')()

# Downloads and converts data from the spreadsheet.
# It can optionally only get data whose Updated is later than 'since'.
getSpreadsheetData = (params) ->
  console.debug "getSpreadsheetData..."
  cache(sessionStorage)('data') ->
    executeAppsScriptFunction('GetChanges')(params...)

# Checks that a spreadsheet is valid, and redirects to the chooser if not,
# rejecting the promise.
checkSpreadsheetData = ({ inventory, orders }) ->
  console.debug "checkSpreadsheetData..."
  unless inventory? and orders?
    chooseSpreadsheet()
    return Promise.reject("Couldn't find INVENTORY/ORDERS on the spreadsheet. Try another one.")
  { inventory, orders }

# Saves the spreadsheet data in the database - resolves to an object with
# orders, inventory, newOrders and newInventory - the latter should have IDs,
# and updated timestamps.
saveSpreadsheetData = ({ orders, inventory }) ->
  console.debug "saveSpreadsheetData...", arguments
  oldOrders = oldInventory = null
  openDB
    .then -> replaceOrders(orders)
    .then -> (newOrders) -> [oldOrders, orders] = [orders, newOrders]
    .then -> replaceInventory(inventory)
    .then -> (newInventory) -> [oldInventory, inventory] = [inventory, newInventory]

# Fixes missing data in orders and inventories (ID, Updated, Order, in ORDERS)
fixSpreadsheetData = ({ oldOrders, oldInventory, orders, inventory }) ->
  console.debug "fixSpreadsheetData..."
  Promise.resolve "Sending the missing IDs"

# Sends the changes to the spreadsheet
updateSpreadsheetData = ({ orders, inventory }) ->
  console.debug "updateSpreadsheetData..."
  Promise.resolve "Sending the changes to the spreadsheet"

# Finds or creates an order.
findOrCreateOrder = (order) ->
  findOrder(order)
    .catch -> createOrder(order)
    .then merge(order)

# Get the changes from the spreadsheet
getSpreadsheetChanges = ->
  console.debug "getSpreadsheetChanges..."
  Promise.resolve()
    .then -> Promise.all([getSpreadsheetID(), getLastSyncedTime()])
    .then getSpreadsheetData
    .then checkSpreadsheetData
    .then saveSpreadsheetData
    .then fixSpreadsheetData
    .then updateSpreadsheetData

# Database section
db = null
openDB = new Promise (resolve, reject) ->
  migrations = [
    (db) ->
      os = db.createObjectStore 'orders', keyPath: 'id', autoIncrement: true
      # os.createIndex 'byOrder', 'order', unique: false
      # os.createIndex 'byCustomer', 'customer', unique: false
      # os.createIndex 'byProduct', 'product', unique: false
      # os.createIndex 'byStatus', 'status', unique: false
      # os.createIndex 'byHoldUntil', 'hold_until', unique: false
      # os.createIndex 'bySoldAt', 'date_sold', unique: false
      # os.createIndex 'byUpdated', 'updated', unique: false
      os = db.createObjectStore 'inventory', keypath: 'product'
      # os.createIndex 'byUpdated', 'updated', unique: false
      # os.createIndex 'byTotal', 'total', unique: false
      # os.createIndex 'byAvailable', 'available', unique: false
      # os.createIndex 'byType', 'type', unique: false
      os = db.createObjectStore 'changes', keypath: 'id', autoIncrement: true
      # os.createIndex 'byObjectType', 'type', unique: false
      # os.createIndex 'byObjectID', 'object_id', unique: false
      # os.createIndex 'byOldValues', 'old_values', unique: false
      # os.createIndex 'byNewValues', 'new_values', unique: false
      # os.createIndex 'byTime', 'time', unique: false
  ]
  migrate = ({ oldVersion, newVersion }) ->
    Promise.all(migration(@result) for migration in migrations[oldVersion..newVersion])
      .then console.debug "Migrated!"
  request = indexedDB.open('stockman', VERSION)
  request.addEventListener 'error', -> reject @error
  request.addEventListener 'success', -> resolve db = @result
  request.addEventListener 'blocked', -> reject @error
  request.addEventListener 'upgradeneeded', migrate


# Gets an authorization token
getAuthToken = ->
  delete sessionStorage.access_token # XXX - dirty hack to force refresh of token
  oauth2rizer(GOOGLE)()

# Gets a function which can execute the given Apps Script function remotely
executeAppsScriptFunction = (functionName) ->
  { scripts_uri, script_id } = GOOGLE
  url = "#{scripts_uri}/#{script_id}:run"
  data = { function: functionName, devMode: true }
  (parameters...) ->
    new Promise (resolve, reject) ->
      load = ->
        response = JSON.parse(@responseText)
        if response.error?
          console.error response.error
          return reject(response.error)
        resolve response.response.result
      error = ->
        response = JSON.parse(@responseText)
        console.error("Error executing Apps Script", @error)
        reject(@error)
      handlers = { load, error }
      data.parameters = parameters
      method = 'post'
      post = (token) ->
        method = 'post'
        headers = { Authorization: "Bearer #{token}" }
        data = JSON.stringify(data)
        ajax.request({ method, url, headers, data, handlers })
      getAuthToken().then(post)

clearStore = (store) ->
  console.debug "clearStore", store
  new Promise (resolve, reject) ->
    openDB.then ->
      request = db.transaction(store, 'readwrite').objectStore(store).clear()
      request.addEventListener 'error', -> reject(@error.message)
      request.addEventListener 'success', -> resolve(@result)

addOne = (store, key) ->
  # console.debug "addOne", store
  (record) ->
    console.debug "addOne(#{store})", record
    new Promise (resolve, reject) ->
      openDB.then ->
        args = [record]
        args.push(record[key]) if key?
        request = db.transaction(store, 'readwrite').objectStore(store).add(args...)
        request.addEventListener 'error', ->
          console.error "Failed to add record to #{store}", record, @error.message
          reject(@error.message)
          throw @error.message
        request.addEventListener 'success', ->
          #console.debug "Added record to #{store}", record, @result
          resolve(@result)

addAll = (store, key) ->
  #console.debug "addAll", store
  (records) ->
    #console.debug "addAll(#{store})", records
    Promise.all(addOne(store, key)(record) for record in records)

replaceInventory = (products) ->
  clearStore('inventory').then ->
    addAll('inventory', 'product')(new Product(p) for p in products)

replaceOrders = (orderItems) ->
  clearStore('orders').then ->
    addAll('orders')(new OrderItem(o) for o in orderItems)

console.log "Welcome to stockman v#{VERSION}"
@Stockman = { VERSION, utils, ui, db }
start()
