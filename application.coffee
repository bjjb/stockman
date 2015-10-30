VERSION = 1
DEBUG = 1

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
debug = (args...) ->
  if DEBUG
    console.debug(args...)
    ul = document.getElementById('logs')
    li = document.createElement('LI')
    li.innerHTML = "<pre>#{JSON.stringify(args)}</pre>"
    ul.insertBefore(li, ul.firstChild)
  args
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
OrderItem::getPrice = Number(@price ? 0).toFixed(2)
OrderItem::bsClass = ->
  switch @status
    when 'SOLD' then 'success'
    when 'OPEN' then 'info'
    when 'HOLD' then 'warning'
    when 'SHORT' then 'success'
    else 'default'
OrderItem::action = ->
  switch @status
    when 'OPEN' then 'Sell'
    when 'SOLD' then 'Undo'
    else 'Open'
OrderItem::isSold = -> @status is 'SOLD'
OrderItem::isOpen = -> @status is 'OPEN'
OrderItem::isHold = -> @status is 'HOLD'
OrderItem::isShort = -> @status is 'SHORT'
OrderItem::context = ->
  switch @status
    when 'OPEN' then 'info'
    when 'HOLD' then 'warning'
    when 'SHORT' then 'danger'
    when 'SOLD' then 'success'
    else 'default'
OrderItem::getTotal = ->
  total = 0
  total += Number(item.getPrice()) for item in @items
  total.toFixed(2)

Product = (data) ->
  @[k] = v for own k, v of data when v isnt ''
  @[k] = new Date(@[k]) for k in ['updated'] when @[k]
  @

Order = ({ @customer, @id }) ->
  @orderItems = []
  @
Order::status = ->
  return 'CLOSED' if @orderItems?.every (i) -> i.status in ['SOLD']
  'OPEN'
Order::context = ->
  switch @status()
    when 'OPEN' then 'info'
    when 'CLOSED' then 'default'
Order::bsClass = ->
  switch @status()
    when 'OPEN' then 'panel-info'
    when 'CLOSED' then 'panel-default'
Order::items = -> @orderItems
Order::items.open = -> i for i in @items when i.status is 'OPEN'
Order::items.sold = -> i for i in @items when i.status is 'SOLD'
Order::items.hold = -> i for i in @items when i.status is 'HOLD'
Order::items.short = -> i for i in @items when i.status is 'SHORT'
  
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
  removeClass = (qs...) ->
    (classes...) ->
      for q in qs
        for e in $$(q)
          for c in classes
            e.classList.remove(x) for x in e.classList when x?.match(new RegExp("^#{c}$"))
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
  window.addEventListener 'DOMContentLoaded', ->
    resolve(ui = UI(@))

# Handles UI events on the #orders element
ordersHandler = (event) ->
  { type, target } = event
  { name, id, classList, dataset, nodeName } = target
  if type is 'click'
    if nodeName is 'A' and dataset.action?
      event.preventDefault()
      form = target
      form = form.parentElement until form.nodeName is 'FORM'
      setOrderItemAction(form, dataset.action)
    if nodeName is 'BUTTON' and dataset.action?
      { orderitem } = dataset
      event.preventDefault()
      switch dataset.action
        when 'Sell' then sellOrderItem(target)
        when 'Open' then openOrderItem(target)
        when 'Hold' then holdOrderItem(target)
        when 'Short' then shortOrderItem(target)
        when 'Undo' then undoLastOrderItemAction(target)
        when 'Checkout' then checkoutOrderItem(target)
  if type is 'input'
    if target.name is 'price'
      updateOrderItemPrice(target)
    else if target.name is 'filter'
      filterOrders(target.value)
  if type is 'submit'
    event.preventDefault()
    if target.name is 'filter'
      filterOrders(target.value)
    if target.name is 'price'
      updateOrderItemPrice(target.price)
    

inventoryHandler = (event) ->
  { target } = event

# Starts the whole thing
start = ->
  Promise.resolve()
    .then synchronize
    .then renderInventory
    .then renderOrders
    .then -> ui.listen('#orders')('click')(ordersHandler)
    .then -> ui.listen('#orders')('input')(ordersHandler)
    .then -> ui.listen('#orders')('submit')(ordersHandler)
    .then -> ui.listen('#inventory')('click')(inventoryHandler)

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
  debug "renderInventory..."
  getUI
    .then getInventoryForUI
    .then (products) -> ui.render('#inventory tbody.products')({products})

# Render the orders section
renderOrders = ->
  getUI
    .then getOrdersForUI
    .then (orders) -> ui.render('#orders div.orders')({orders})

# Gets the inventory from the database
getInventoryForUI = ->
  getAll('inventory')().then (products) ->
    new Product(p) for p in products

# Gets the orders from the database, and makes Orders objects
getOrdersForUI = ->
  getAll('orders')().then (orderItems) ->
    orderItems = (new OrderItem(o) for o in orderItems)
    orders = {}
    for orderItem, id in orderItems
      order_id = orderItem.getOrderID()
      { customer } = orderItem
      order = orders[order_id] ?= new Order({ customer, id })
      orderItem.order = order
      orderItem.order_id = id
      order.orderItems.push(orderItem)
    (v for own k, v of orders when v.status() isnt 'CLOSED')

# Gets a function to merge the second argument into the first
merge = (first) ->
  (second) ->
    first[k] = v for own k, v of second
    first

getChanges = ->
  debug "Getting changes..."

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
  debug "Syncing changes to DB", changes
  

# Show that some synchronization is happening
showSynchronizing = ->
  getUI.then ->
    ui.addClass('body')('synchronizing')
    ui.addClass('.alerts .synchronizing')('working')

# Show that the synchronizing has finished
showSynchronizationSuccess = ->
  getUI.then ->
    ui.replaceClass('.alerts .synchronizing')('working')('success')
    setTimeout((-> ui.removeClass('body')('synchronizing')), 5000)

# Show that the synchronizing has failed
showSynchronizationFailure = (reason) ->
  getUI.then ->
    console.error reason
    debug reason, Error()
    ui.replaceClass('.alerts .synchronizing')('working')('error')
    ui.$('.alerts .synchronizing .reason').innerHTML = reason
    setTimeout((-> ui.removeClass('body')('synchronizing')), 5000)

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
localStorage.spreadsheet_id = "1hFU6T4UsSHaD8GMTpPEFMFcbQbHtsqX-jhQNXX-00bI"

# Shows the spreadsheet chooser.
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
      return Promise.resolve(JSON.parse(storage.getItem(key))) if storage[key]
      f().then (result) ->
        storage.setItem(key, JSON.stringify(result)) if DEBUG?
        result

# Gets a list of spreadsheets in the user's Google Drive
getUserSpreadsheets = ->
  cache(localStorage)('spreadsheets') ->
    executeAppsScriptFunction('SpreadsheetFiles')()

# Downloads and converts data from the spreadsheet.
# It can optionally only get data whose Updated is later than 'since'.
getSpreadsheetData = (params) ->
  debug "getSpreadsheetData..."
  cache(localStorage)('data') ->
    executeAppsScriptFunction('GetChanges')(params...)

# Checks that a spreadsheet is valid, and redirects to the chooser if not,
# rejecting the promise.
checkSpreadsheetData = ({ inventory, orders }) ->
  debug "checkSpreadsheetData..."
  unless inventory? and orders?
    chooseSpreadsheet()
    return Promise.reject("Couldn't find INVENTORY/ORDERS on the spreadsheet. Try another one.")
  { inventory, orders }

# Saves the spreadsheet data in the database - resolves to an object with
# orders, inventory, newOrders and newInventory - the latter should have IDs,
# and updated timestamps.
saveSpreadsheetData = ({ orders, inventory }) ->
  debug "saveSpreadsheetData...", arguments
  oldOrders = oldInventory = null
  openDB
    .then -> replaceOrders(orders)
    .then -> (newOrders) -> [oldOrders, orders] = [orders, newOrders]
    .then -> replaceInventory(inventory)
    .then -> (newInventory) -> [oldInventory, inventory] = [inventory, newInventory]

# Fixes missing data in orders and inventories (ID, Updated, Order, in ORDERS)
fixSpreadsheetData = ({ oldOrders, oldInventory, orders, inventory }) ->
  debug "fixSpreadsheetData..."
  Promise.resolve "Sending the missing IDs"

# Sends the changes to the spreadsheet
updateSpreadsheetData = ({ orders, inventory }) ->
  debug "updateSpreadsheetData..."
  Promise.resolve "Sending the changes to the spreadsheet"

# Finds or creates an order.
findOrCreateOrder = (order) ->
  findOrder(order)
    .catch -> createOrder(order)
    .then merge(order)

# Get the changes from the spreadsheet, and update the database
getSpreadsheetChanges = ->
  debug "getSpreadsheetChanges..."
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
      os.createIndex 'byStatus', 'status', unique: false
      os = db.createObjectStore 'inventory', keypath: 'product'
      os.createIndex 'byType', 'type', unique: false
      os = db.createObjectStore 'changes', keypath: 'id', autoIncrement: true
      os.createIndex 'byTime', 'time', unique: false
  ]
  migrate = ({ oldVersion, newVersion }) ->
    Promise.all(migration(@result) for migration in migrations[oldVersion..newVersion])
      .then debug "Migrated!"
  request = indexedDB.open('stockman', VERSION)
  request.addEventListener 'error', -> reject @error
  request.addEventListener 'success', -> resolve db = @result
  request.addEventListener 'blocked', -> reject @error
  request.addEventListener 'upgradeneeded', migrate


# Gets an authorization token
getAuthToken = ->
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
  debug "clearStore", store
  new Promise (resolve, reject) ->
    openDB.then ->
      request = db.transaction(store, 'readwrite').objectStore(store).clear()
      request.addEventListener 'error', -> reject(@error.message)
      request.addEventListener 'success', -> resolve(@result)

addOne = (store, key) ->
  (record) ->
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
          resolve(@result)

addAll = (store, key) ->
  (records) ->
    Promise.all(addOne(store, key)(record) for record in records)

replaceInventory = (products) ->
  clearStore('inventory').then ->
    addAll('inventory', 'product')(new Product(p) for p in products)

replaceOrders = (orderItems) ->
  clearStore('orders').then ->
    addAll('orders')(new OrderItem(o) for o in orderItems)

filterOrders = (match) ->
  rex = new RegExp("#{match}", "i")
  orders = ui.$$('#orders .order')
  for order in orders
    customerName = ui.$("##{order.id} .customer").innerText
    order.hidden = !customerName.match(rex)

setOrderItemAction = (form, action) ->
  button = form.querySelector('button.action')
  button.dataset.action = action
  button.innerHTML = action
  buttons = form.querySelectorAll('button')
  context = switch action
    when "Sell" then "success"
    when "Hold" then "warning"
    when "Open" then "primary"
    when "Short" then "danger"
    when "Delete" then "danger"
    else throw "Can't get context for action #{action}"
  for button in buttons
    button.classList.remove('btn-success')
    button.classList.remove('btn-warning')
    button.classList.remove('btn-primary')
    button.classList.remove('btn-danger')
    button.classList.add("btn-#{context}")

sellOrderItem = (target) ->
  { dataset: { orderitem }, form } = target
  ui.addClass("#order-item-#{orderitem}")('selling')
  ui.$("#order-item-#{orderitem} form.selling [name='price']").focus()

updateOrderItemPrice = (target) ->
  { dataset: { orderitem }, form, value } = target
  { order } = form.dataset
  form.sell.disabled = !value
  output = ui.$("#order-item-#{orderitem} form.sold").price
  value = Number(value or 0).toFixed(2)
  output.setAttribute('value', value)
  output.innerHTML = "$ #{value}"
  updateOrderPrice(order)

updateOrderPrice = (order) ->
  prices = (Number(e.value or 0) for e in ui.$$("#order-#{order} input[name='price']"))
  total = 0
  total += Number(price or 0) for price in prices
  output = ui.$("#order-#{order} output[name='total']")
  output.setAttribute('value', total)
  output.innerHTML = "$ #{total.toFixed(2)}"

console.log "Welcome to stockman v#{VERSION}"
@Stockman = { VERSION, utils, ui, db }
start()
