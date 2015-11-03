VERSION = 2
DEBUG = 1
ERRORS = []

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

# Writes stuff to the console and to the logs
debug = (args...) ->
  if sessionStorage.debug
    console?.debug(args...)
    getUI.then ->
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
random = (a) -> a[Math.floor(Math.random() * a.length)]
utils = { rejolve, urlencode, ajax, taskChain, arrayify, getProperty, putProperty, random }

errors = []
logs = []
changes = []
p = console.debug.bind(console)

Stockman = { errors, logs, changes, p }

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

Product = (data, @id) ->
  @[k] = v for own k, v of data when v isnt ''
  @[k] = new Date(@[k]) for k in ['updated'] when @[k]
  @
Product::status = ->
  if @available is 0 then return 'warning'
  if @available < 0 then return 'danger'

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
  
ui = null
# A promise that resolves when the window is loaded
getUI = new Promise (resolve, reject) ->
  window.addEventListener 'DOMContentLoaded', ->
    resolve(Stockman.ui = ui = MVStar(@))

# Handles UI events on the #orders element
ordersHandler = (event) ->
  { type, target } = event
  { name, id, classList, dataset, nodeName } = target
  if type is 'click'
    if nodeName is 'A' and dataset.action?
      event.preventDefault()
      setOrderItemAction(target)
    if nodeName is 'BUTTON' and target.type is 'button' and dataset.action?
      { orderitem } = dataset
      switch dataset.action
        when 'Sell' then sellOrderItem(target)
        when 'Open' then openOrderItem(target)
        when 'Hold' then holdOrderItem(target)
        when 'Short' then shortOrderItem(target)
        when 'Delete' then deleteOrderItem(target)
        when 'Undo' then unsellOrderItem(target)
    if nodeName is 'SPAN' and id is 'clear-filter'
      form = ui.$('#orders form[name="filter"]')
      form.reset()
      filterOrders(form.filter.value)
  if type is 'input'
    if target.name is 'price'
      updateOrderItemPrice(target)
    else if target.name is 'filter'
      filterOrders(target.value)
  if type is 'submit'
    event.preventDefault()
    switch target.name
      when 'filter' then filterOrders(target.filter.value)
      when 'sell' then soldOrderItem(target)
      else throw "Unhandled #orders submit: #{target.name}"
    
inventoryHandler = (event) ->
  { target, type } = event
  { name, id, classList, dataset, nodeName } = target
  classNames = (className for className in classList)
  if type is 'click'
    console.debug target
    if nodeName is 'SPAN' and id is 'clear-filter'
      form = ui.$('#inventory form[name="filter"]')
      form.reset()
      filterProducts(form.filter.value)
      return
    if nodeName is 'TD'
      if 'total' in classNames
        tr = target.parentElement
        product = tr.querySelector('td.product').innerHTML
        available = target.innerHTML
        ui.$('#inventory .modal .product').innerHTML = product
        ui.$('#inventory .modal input').value = available
        $('#inventory .modal').modal('show')
  if type is 'input'
    if target.name is 'filter'
      filterProducts(target.value)
  if type is 'submit'
    event.preventDefault()
    switch target.name
      when 'filter' then filterProducts(target.filter.value)
      else throw "Unhandled #inventory submit: #{target.name}"

loadingHandler = (event) ->
  { target, type } = event
  console.debug type, target, event, @

  switch type
    when 'checking'
      ui.addClass('#loading')(type)
    when 'noupdate'
      ui.replaceClass('#loading')('checking')(type)
    when 'downloading'
      ui.replaceClass('#loading')('checking')(type)
    when 'progress'
      { loaded, total, lengthComputable } = event
      progress = ui.$('#loading progress')
      progress.max = total
      progress.value = loaded
    when 'cached'
      ui.replaceClass('#loading')('downloading')(type)
    when 'updateready'
      ui.replaceClass('#loading')('downloading')(type)
    when 'obsolete'
      ui.replaceClass('#loading')('checking')(type)
    when 'error'
      ui.replaceClass('#loading')('checking')(type)

chooseSpreadsheetHandler = (event) ->
  { type, target } = event
  switch type
    when 'change'
      { value } = target
      ui.hide('.alerts .synchronizing')
      ui.$('#choose-spreadsheet form .help').innerHTML = "Checking spreadsheet..."
      ui.show('#choose-spreadsheet form .spinner')
      checkSpreadsheet(value)
        .then ({ orders, inventory }) ->
          ui.hide('#choose-spreadsheet form .spinner')
          sessionStorage.spreadsheet = JSON.stringify({ orders, inventory })
          ui.replaceClass('#choose-spreadsheet form')('has-error', 'has-warning')('has-success')
          ui.enable('#choose-spreadsheet button')
          ui.$('#choose-spreadsheet form .help').innerHTML = "Spreadsheet looks good!"
        .catch (message) ->
          ui.hide('#choose-spreadsheet form .spinner')
          ui.replaceClass('#choose-spreadsheet form')('has-success', 'has-warning')('has-error')
          ui.disable('#choose-spreadsheet form button')
          ui.$('#choose-spreadsheet form .help').innerHTML = "That spreadsheet appears invalid."

checkSpreadsheet = (id) ->
  getSpreadsheetData(id).then ({ inventory, orders }) ->
    unless inventory? and orders?
      throw "The spreadsheet must have sheets for Orders and for Inventory."
    { inventory, orders }

# Starts the whole thing
start = ->
  getUI
    .then initialize # start from scratch, if needed
    .then synchronize # pull in database changes
    .then renderInventory
    .then renderOrders
    .then renderDashboard
    .then -> ui.listen('#orders')('click', 'input', 'submit')(ordersHandler)
    .then -> ui.listen('#inventory')('click', 'input', 'submit')(inventoryHandler)
    .then -> ui.listen('#loading')('click')(loadingHandler)
    .then -> ui.goto('#dashboard')

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
  getUI
    .then getInventoryForUI
    .then (products) -> ui.render('#inventory tbody.products')({products})

# Render the orders section
renderOrders = ->
  getUI
    .then getOrdersForUI
    .then (orders) -> ui.render('#orders div.orders')({orders})

# Render the dashboard
renderDashboard = ->
  getUI
    .then getDashboardForUI
    .then ui.render('#dashboard .statuses')
# Gets the inventory from the database
getInventoryForUI = ->
  openDB.then (db) ->
    db.inventory.type.getAll().then (products) ->
      new Product(p, i) for p, i in products

# Gets the orders from the database, and makes Orders objects
getOrdersForUI = ->
  openDB.then (db) ->
    db.orders.getAll().then (orderItems) ->
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

# Gets the numbers of openOrders, heldOrders, shortOrders, and a random
# message about the state of the inventory.
getDashboardForUI = ->
  dashboard = { orders: {}, inventory: {} }
  openDB.then (db) ->
    Promise.all([
      db.orders.status.count('OPEN').then (n) -> dashboard.orders.open = n
      db.orders.status.count('HOLD').then (n) -> dashboard.orders.hold = n
      db.orders.status.count('SHORT').then (n) -> dashboard.orders.short = n
      db.inventory.available.getAll([null, -1]).then (p) -> dashboard.inventory.short = p
      db.inventory.available.getAll(0).then (p) -> dashboard.inventory.out = p
    ]).then ->
      { orders, inventory } = dashboard
      { short, out } = dashboard.inventory
      inventory.message = "You're #{-sp.available} short on #{sp.product}" if sp = short.shift()
      inventory.message += " and #{short.length} other products" if short.length
      return dashboard if inventory.message?
      inventory.message = "You're out of #{sp.product}" if op = out.shift()
      inventory.message += " and #{out.length} other products" if out.length
      inventory.message ?= "The inventory looks good!"
      dashboard
      
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
  indexedDB.deleteDatabase('stockman') unless lastSynced
  new Date(lastSynced) if lastSynced?

# Gets the ID of the spreadsheet - tries to get it from localStorage, shows
# the chooser otherwise.
getSpreadsheetID = ->
  new Promise (resolve, reject) ->
    { spreadsheet_id } = localStorage
    return resolve(spreadsheet_id) if spreadsheet_id
    chooseSpreadsheet(resolve, reject)

chooseSpreadsheet = (resolve) ->
  ui.listen('#choose-spreadsheet')('change')(chooseSpreadsheetHandler)
  ui.hide('.alerts .synchronizing')
  ui.addClass('#choose-spreadsheet')('downloading')
  ui.goto('#choose-spreadsheet')
  getUserSpreadsheets().then (spreadsheets) ->
    ui.render('#choose-spreadsheet select')({ spreadsheets })
    ui.replaceClass('#choose-spreadsheet')('downloading')('updateready')
    ui.listen('#choose-spreadsheet form')('submit') (event) ->
      event.preventDefault()
      ui.show('.alerts .synchronizing')
      resolve(localStorage.spreadsheet_id = @spreadsheet.value)
  
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
getSpreadsheetData = (id, since) ->
  cache(sessionStorage)('spreadsheet') ->
    console.debug "Getting spreadsheet data...", id, since
    executeAppsScriptFunction('GetChanges')(id, since)

# Saves the spreadsheet data in the database - resolves to an object with
# orders, inventory, newOrders and newInventory - the latter should have IDs,
# and updated timestamps.
saveSpreadsheetData = ({ orders, inventory }) ->
  console.debug "saveSpreadsheetData", arguments
  oldOrders = oldInventory = null
  openDB
    .then -> replaceOrders(orders)
    .then -> replaceInventory(inventory)

# Fixes missing data in orders and inventories (ID, Updated, Order, in ORDERS)
fixSpreadsheetData = ({ oldOrders, oldInventory, orders, inventory }) ->
  Promise.resolve "Sending the missing IDs"

# Sends the changes to the spreadsheet
updateSpreadsheetData = ({ orders, inventory }) ->
  Promise.resolve "Sending the changes to the spreadsheet"

# Finds or creates an order.
findOrCreateOrder = (order) ->
  findOrder(order)
    .catch -> createOrder(order)
    .then merge(order)

# Get the changes from the spreadsheet, and update the database
getSpreadsheetChanges = ->
  Promise.resolve()
    .then -> Promise.all([getSpreadsheetID(), getLastSyncedTime()])
    .then (params) -> getSpreadsheetData(params...)
    .then saveSpreadsheetData
    .then fixSpreadsheetData
    .then updateSpreadsheetData

# Database section
db = null
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
  console.debug "keyRange", arg
  return IDBKeyRange.only(arg) unless arg instanceof Array
  [lower, upper] = arg
  if lower?
    if upper?
      console.log "keyRange.bound", arg
      IDBKeyRange.bound(lower, upper)
    else
      console.log "keyRange.lowerBound", arg
      IDBKeyRange.lowerBound(lower)
  else
    console.log "keyRange.upperBound", arg
    IDBKeyRange.upperBound(upper)

openDB = new Promise (resolve, reject) ->
  migrations = [
    (e) ->
      { result } = e
      os = result.createObjectStore 'orders', keyPath: 'id', autoIncrement: true
      os.createIndex 'status', 'status', unique: false
      os.createIndex 'order', 'order', unique: false
      os.createIndex 'customer', 'customer', unique: false
      os = result.createObjectStore 'inventory', keyPath: 'product'
      os.createIndex 'type', 'type', unique: false
      os.createIndex 'total', 'total', unique: false
      os.createIndex 'available', 'available', unique: false
      os = result.createObjectStore 'changes', keyPath: 'id', autoIncrement: true
      os.createIndex 'time', 'time', unique: false
    (e) ->
      { transaction } = e
      os = transaction.objectStore('orders')
      os.createIndex 'product', 'product', unique: false
      os.createIndex 'order_status', 'order_status', unique: false
      os.createIndex 'qty', 'qty', unique: false
      os.createIndex 'hold_until', 'hold_until', unique: false
      os.createIndex 'delivery_location', 'delivery_location', unique: false
      os.createIndex 'date_sold', 'date_sold', unique: false
      os.createIndex 'updated', 'updated', unique: false
      os = transaction.objectStore('inventory')
      os.createIndex 'hold', 'hold', unique: false
      os.createIndex 'open', 'open', unique: false
      os.createIndex 'updated', 'updated', unique: false
  ]
  migrate = ({ oldVersion, newVersion }) ->
    console.log "Migrating from #{oldVersion} → #{newVersion}"
    Promise.all(migration(@) for migration in migrations[oldVersion...newVersion])
      .then console.log("Migrated!")
  request = indexedDB.open('stockman', VERSION)
  request.addEventListener 'error', ->
    console.error arguments, @
    reject @error.message
  request.addEventListener 'success', ->
    resolve(db = Stockman.db = new IndexTheBee(@result))
  request.addEventListener 'blocked', ->
    console.error arguments, @
    reject @error.message
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
        errors.push(executeAppsScriptFunction, @error)
        reject(@error.details.join('; '))
      handlers = { load, error }
      data.parameters = parameters
      method = 'post'
      post = (token) ->
        method = 'post'
        headers = { Authorization: "Bearer #{token}" }
        data = JSON.stringify(data)
        ajax.request({ method, url, headers, data, handlers })
      getAuthToken().then(post)

replaceInventory = (products) ->
  db.inventory.clear().then ->
    Promise.all(db.inventory.add(new Product(p)) for p in products)

replaceOrders = (orderItems) ->
  db.orders.clear().then ->
    Promise.all(db.orders.add(new OrderItem(o)) for o in orderItems)

filterOrders = (match) ->
  rex = new RegExp("#{match}", "i")
  orders = ui.$$('#orders .order')
  for order in orders
    customerName = ui.$("##{order.id} .customer").innerText
    order.hidden = !customerName.match(rex)

filterProducts = (match) ->
  rex = new RegExp("#{match}", "i")
  products = ui.$$('#inventory tr.product')
  for product in products
    productName = product.querySelector('.product').innerText
    product.hidden = !productName.match(rex)

setOrderItemAction = (target) ->
  console.debug "Setting action on ", target
  { dataset } = target
  { orderitem, action } = dataset
  form = target
  form = form.parentElement until form.nodeName is 'FORM'
  formClass = c for c in form.classList when c in ['hold', 'sell', 'short', 'selling', 'open', 'undo', 'delete']
  context = switch action
    when "Sell" then "success"
    when "Hold" then "warning"
    when "Open" then "primary"
    when "Short" then "danger"
    when "Delete" then "danger"
    else throw "Can't get context for action #{action}"
  ui.replaceClass("#order-item-#{orderitem} form.#{formClass} button[type='button']")('btn-success', 'btn-warning', 'btn-primary', 'btn-danger')("btn-#{context}")
  button = ui.$("#order-item-#{orderitem} form.#{formClass} button[name='action']")
  button.dataset.action = action
  button.innerHTML = action
  button.value = action

sellOrderItem = (target) ->
  { dataset: { orderitem }, form } = target
  ui.addClass("#order-item-#{orderitem}")('selling')
  ui.$("#order-item-#{orderitem} form.selling [name='price']").focus()

openOrderItem = (target) ->
  { dataset: { orderitem }, form } = target
  orderitem = Number(orderitem)
  db.orders.get(orderitem).then (object) ->
    object.status = 'OPEN'
    db.orders.put(object).then ->
      ui.replaceClass("#order-item-#{orderitem}")('selling', 'SOLD', 'SHORT', 'HOLD')('OPEN')
      changes.push(['change', 'order', 'status', 'OPEN'])

holdOrderItem = (target) ->
  { dataset: { orderitem }, form } = target
  orderitem = Number(orderitem)
  db.orders.get(orderitem).then (object) ->
    object.status = 'HOLD'
    db.orders.put(object).then ->
      ui.replaceClass("#order-item-#{orderitem}")('selling', 'SOLD', 'SHORT', 'OPEN')('HOLD')
      changes.push(['change', 'order', 'status', 'HOLD'])

shortOrderItem = (target) ->
  { dataset: { orderitem }, form } = target
  orderitem = Number(orderitem)
  db.orders.get(orderitem).then (object) ->
    object.status = 'HOLD'
    db.orders.put(object).then ->
      ui.replaceClass("#order-item-#{orderitem}")('selling', 'SOLD', 'OPEN', 'HOLD')('SHORT')
      changes.push(['change', 'order', 'status', 'SHORT'])

deleteOrderItem = (target) ->
  { dataset: { orderitem }, form } = target
  orderitem = Number(orderitem)
  if prompt("Are you sure?")
    db.orders.delete(orderitem).then ->
      console.debug arguments
      ui.hide("#order-item-#{orderitem}")
      changes.push(['delete', 'order', orderitem])

updateOrderItemPrice = (target) ->
  { dataset: { orderitem }, form, value } = target
  { order } = form.dataset
  form.sell.disabled = !value
  output = ui.$("#order-item-#{orderitem} form.sold").price
  value = Number(value or 0).toFixed(2)
  output.setAttribute('value', value)
  output.innerHTML = "$ #{value}"
  changes.push(['change', 'order', 'price', value])
  updateOrderPrice(order)

updateOrderPrice = (order) ->
  prices = (Number(e.value or 0) for e in ui.$$("#order-#{order} input[name='price']"))
  total = 0
  total += Number(price or 0) for price in prices
  output = ui.$("#order-#{order} output[name='total']")
  output.setAttribute('value', total)
  output.innerHTML = "$ #{total.toFixed(2)}"

soldOrderItem = (form) ->
  { order, orderitem } = form.dataset
  ui.replaceClass("#order-item-#{orderitem}")('selling', 'HOLD', 'SHORT', 'OPEN')('SOLD')

for event in 'checking noupdate downloading progress cached updateready obsolete error'.split(' ')
  applicationCache.addEventListener event, loadingHandler

console.log "Welcome to stockman v#{VERSION}"
start()

addEventListener 'online', ->
  getUI.then (ui) ->
    ui.replaceClass('body')('offline')('online')
    setTimeout((-> ui.removeClass('body')('online')), 5000)
addEventListener 'offline', ->
  getUI.then (ui) ->
    ui.replaceClass('body')('online')('offline')

@Stockman = Stockman
@p = console.debug.bind(console)
