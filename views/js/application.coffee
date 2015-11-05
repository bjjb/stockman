VERSION = 1
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

# Very, very simple change tracker.
changes =
  all: (o) -> openDB.then (db) -> db.changes.getAll()
  push: (o) -> openDB.then (db) -> db.changes.add(o, new Date())
  clear: -> openDB.then (db) -> db.changes.clear()
  since: (date) -> openDB.then (db) -> db.changes.getAll([date, null])
  before: (date) -> openDB.then (db) -> db.changes.getAll([null, date])

p = console.debug.bind(console)

Stockman = { errors, logs, changes, p, Order, OrderItem, Product }

OrderItem = ({
  id, order_id, customer, product, qty, weight, price, status, comment,
  hold_until, date_sold, updated
}) ->
  @id = Number(id) if id
  @customer = customer or throw Error("No customer!")
  @order_id = Number(order_id) if order_id
  @product = product or throw Error("No product!")
  @qty = Number(qty) or 1
  @weight = Number(weight) if weight
  @price = Number(price) if price
  throw "Invalid status" unless status in ['OPEN', 'HOLD', 'SHORT', 'SOLD']
  @status = status
  @comment = comment if comment
  @hold_until = new Date(hold_until) if hold_until
  @date_sold = new Date(date_sold) if date_sold
  @updated = if updated then new Date(updated) else new Date()
  @

# Creates an OrderItem in the database.
OrderItem.create = ({
  order_id, customer, product, qty, weight, price, status, comment,
  hold_until, date_sold, updated
}) ->
  orderItem = new OrderItem({
    order_id, customer, product, qty, weight, price, status, comment,
    hold_until, date_sold, updated
  })
  orderItem.save()

# Promises to create or update the OrderItem
OrderItem::save = ->
  @updated = new Date()
  openDB.then (db) =>
    if @id? then db.orderitems.put(@).then => @
    else
      db.orderitems.add(@).then (id) =>
        @id = id
        @

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

Product = ({ product, type, total, available, price, units, comment, updated }) ->
  @product = product or throw "No name given!"
  @type = type if type
  @total = Number(total or 0)
  @available = Number(available or 0)
  @price = Number(price)
  @units = units if units
  @comment = comment if comment
  @updated = new Date(updated) if updated
  @

Product::save = ->
  openDB.then (db) =>
    db.products.put(@)
    @

Product.create = (product) ->
  new Product(product).save()

Product::status = ->
  if @available is 0 then return 'warning'
  if @available < 0 then return 'danger'

Order = ({
  order_id, customer, status, hold_until, delivery_location, date_sold, price,
  comment, updated
}) ->
  @order_id = Number(order_id) if order_id?
  @customer = customer or throw "No customer!"
  @status = 'OPEN'
  delivery_location ?= localStorage.default_delivery_location
  @delivery_location = delivery_location if delivery_location
  @comment = comment if comment
  @price = Number(price) if price
  @hold_until = new Date(hold_until) if hold_until
  @date_sold = new Date(date_sold) if date_sold
  @updated = if updated then new Date(updated) else new Date()
  @

Order.create = ({
  customer, status, hold_until, delivery_location, date_sold, price, comment,
  updated
}) ->
  new Order({
    customer, status, hold_until, delivery_location, date_sold, price,
    comment, updated
  }).save()

Order::save = ->
  @updated = new Date()
  openDB.then (db) =>
    if @order_id
      db.orders.put(@).then => @
    else
      db.orders.add(@).then (id) =>
        @order_id = id
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

applicationCacheHandler = (event) ->
  { target, type } = event
  switch type
    when 'checking'
      getUI.then (ui) -> ui.addClass('#loading')('checking')
    when 'noupdate'
      getUI.then (ui) -> ui.replaceClass('#loading')('checking')('noupdate')
    when 'downloading'
      getUI.then (ui) -> ui.replaceClass('#loading')('checking')('downloading')
    when 'progress'
      { loaded, total, lengthComputable } = event
      getUI.then (ui) ->
        if progress = ui.$('progress.appcache')
          progress.max = total
          progress.value = loaded
    when 'cached'
      getUI.then (ui) -> ui.replaceClass('#loading')('downloading')('cached')
    when 'updateready'
      getUI.then (ui) -> ui.replaceClass('#loading')('downloading')('updateready')
    when 'obsolete'
      getUI.then (ui) -> ui.replaceClass('#loading')('checking')('obsolete')
    when 'error'
      getUI.then (ui) -> ui.replaceClass('#loading')('checking')('error')

spreadsheetHandler = (event) ->
  { type, target } = event
  switch type
    when 'change'
      { value } = target
      ui.replaceClass('#choose-spreadsheet')('error', 'updateready')('checking')
      ui.disable target
      checkSpreadsheet(value)
        .then ({ orders, inventory }) ->
          ui.enable target
          ui.replaceClass('#choose-spreadsheet')('checking')('updateready')
          ui.replaceClass('#choose-spreadsheet form')('has-error', 'has-warning')('has-success')
          ui.enable('#choose-spreadsheet button')
          sessionStorage.spreadsheet = JSON.stringify({ orders, inventory }) # cache it
        .catch (message) ->
          ui.enable target
          ui.replaceClass('#choose-spreadsheet')('checking')('error')
          ui.replaceClass('#choose-spreadsheet form')('has-success', 'has-warning')('has-error')
          ui.disable('#choose-spreadsheet form button')
    when 'submit'
      event.preventDefault()
      { spreadsheet, submit } = target
      localStorage.spreadsheet = spreadsheet.value # save the spreadsheet ID
      spreadsheet = JSON.parse(sessionStorage.spreadsheet)
      delete sessionStorage.spreadsheet # delete the cached version
      ui.addClass('body')('synchronizing')
      importSpreadsheet(spreadsheet)
      ui.goto '#dashboard'

checkSpreadsheet = (id) ->
  getSpreadsheetData(id).then ({ inventory, orders }) ->
    unless inventory? and orders?
      throw "The spreadsheet must have sheets for Orders and for Inventory."
    { inventory, orders }

importSpreadsheet = ({ orders, inventory }) ->
  Promise.resolve({ orders, inventory })
    .then fixData
    .then saveData
    
# Starts the whole thing
start = ->
  synchronize() # pull in database changes

showError = (message) ->
  console.error(if message instanceof Error then message else Error(message))
  getUI.then (ui) ->
    ui.addClass('body')('error')
    ui.$('.alert.error .message').innerHTML = message.toString()

# Synchronize the local database with the spreadsheet
synchronize = ->
  showSynchronizing = -> getUI.then (ui) -> ui.addClass('body')('synchronizing')
  hideSynchronizing = -> getUI.then (ui) -> ui.removeClass('body')('synchronizing')
  failSynchronizing = (reason) -> hideSynchronizing().then -> showError(reason)

  Promise.resolve()
    .then showSynchronizing
    .then getSpreadsheetChanges
    .then importSpreadsheet
    .then getChanges
    .then updateSpreadsheet
    .then hideSynchronizing
    .catch failSynchronizing

# Render the inventory section
renderInventory = ->
  console.debug "Rendering inventory..."
  getUI
    .then getInventoryForUI
    .then ui.render('#inventory tbody.products')

# Render the settings section
renderSettings = ->
  console.debug "Rendering settings..."
  getUI
    .then getSettingsForUI
    .then ui.render('#settings')

# Render the orders section
renderOrders = ->
  console.debug "Rendering orders..."
  getUI
    .then getOrdersForUI
    .then ui.render('#orders')

# Render the dashboard
renderDashboard = ->
  console.debug "Rendering dashboard..."
  getUI
    .then getDashboardForUI
    .then ui.render('#dashboard')

# Gets the inventory from the database
getInventoryForUI = ->
  openDB.then (db) ->
    db.products.type.getAll().then (products) ->
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
      db.orderitems.status.count('OPEN').then (n) -> dashboard.orders.open = n
      db.orderitems.status.count('HOLD').then (n) -> dashboard.orders.hold = n
      db.orderitems.status.count('SHORT').then (n) -> dashboard.orders.short = n
      db.products.available.getAll([null, -1]).then (p) -> dashboard.inventory.short = p
      db.products.available.getAll(0).then (p) -> dashboard.inventory.out = p
    ]).then ->
      { orders, inventory } = dashboard
      { short, out } = dashboard.inventory
      inventory.message = "You're #{-sp.available} short on #{sp.product}" if sp = short.shift()
      inventory.message += " and #{short.length} other products" if short.length
      return dashboard if inventory.message?
      inventory.message = "You're out of #{sp.product}" if op = out.shift()
      inventory.message += " and #{out.length} other products" if out.length
      inventory.message ?= "The inventory looks good!"
      console.debug dashboard
      dashboard
      
# Gets a function to merge the second argument into the first
merge = (first) ->
  (second) ->
    first[k] = v for own k, v of second
    first

# Gets a list of changes since the last time the app was synced (or all of
# them, if it was never synced).
getChanges = ->
  changes.all()

# Converts a list of changes into arguments that can be passed along to the
# Apps Script.
formatDatabaseChanges = (changes) ->
  changeToScriptParams(change) for change in changes

# Updates the spreadsheet with the values supplied
# Changes should be arrays containing [SET,<id>,<property>,<value>,...]
# To delete, send ['DELETE',<id>]
# To add, send ['ADD',<id>,<property>,<value>,...]
updateSpreadsheet = (changes) ->
  getSpreadsheetID().then (ssid) ->
    executeAppsScriptFunction("ApplyChanges", ssid, changes)
      .then -> changes.clear()
      .then -> localStorage.lastSynced = new Date()

# Gets the time the app and the spreadsheet were last synced.
getLastSyncedTime = ->
  { lastSynced } = localStorage
  new Date(lastSynced) if lastSynced?

# Gets the ID of the spreadsheet - tries to get it from localStorage, shows
# the chooser otherwise.
getSpreadsheetID = ->
  new Promise (resolve, reject) ->
    { spreadsheet } = localStorage
    return resolve(spreadsheet) if spreadsheet
    getUI.then (ui) ->
      ui.goto('#settings')
      reject()

chooseSpreadsheet = ->
  getUI.then (ui) ->
    ui.addClass('#choose-spreadsheet')('downloading')
    ui.disable('#spreadsheet-select')
    getUserSpreadsheets().then (spreadsheets) ->
      ui.render('#spreadsheet-select')({ spreadsheets })
      ui.enable('#spreadsheet-select')
      ui.replaceClass('#choose-spreadsheet')('downloading')('updateready')
  
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
  cache(sessionStorage)('spreadsheets') ->
    executeAppsScriptFunction('SpreadsheetFiles')()

# Downloads and converts data from the spreadsheet.
# It can optionally only get data whose Updated is later than 'since'.
getSpreadsheetData = (id, since) ->
  console.debug "Getting spreadsheet data...", id, since
  executeAppsScriptFunction('GetChanges')(id, since)

# Assigns IDs to order items which don't have them. They get saved as part of
# the process. Returns a function that expects orderitems, and will resolve tp
# them after they're all fixed.
fixMissingIDs = (orderitems) ->
  fix = (o, i) ->
    o.save().then ({ id, updated }) -> [i, 'id', id, 'updated', updated ]
  Promise.all(fix(o, i) for o, i in orderitems when !o.id).then (fixes) ->
    getSpreadsheetID()
      .then (ssid) -> executeAppsScriptFunction("SetRowProperties")(ssid, { 'ORDERS': fixes })
      .then -> orderitems

# Makes missing orders for order items, and assigns the order_id to the order
# item, after updating the spreadsheet.
fixMissingOrderIDs = (orderitems) ->
  orders = {} # Promises to create orders, grouped by customer
  fix = (o, i) ->
    Promise.resolve(orders[o.customer] ?= Order.create(o)).then ({order_id}) -> [ i, 'order_id', o.order_id = order_id ]
  # 1. ensure the orders and items which have IDs actually exist in the DB
  Promise.all [
    Promise.all((new Order(o).save()) for o in orderitems when o.order_id)
    Promise.all((new OrderItem(o).save()) for o in orderitems when o.id)
  ]
    # 2. then create orders for the items with no order_id (grouped by
    # customer)
    .then -> Promise.all(fix(o, i) for o, i in orderitems when !o.order_id).then (fixes) ->
      # 3. update the database with the new order_ids
      getSpreadsheetID()
        .then (ssid) -> executeAppsScriptFunction("SetRowProperties")(ssid, { 'ORDERS': fixes })
        .then -> orderitems

saveData = ({ orderitems, products }) ->
  Promise.resolve({ orderitems, products })
    .then Promise.all(order.save() for order in orderitems)
    .then Promise.all(product.save() for product in products)
    .then -> console.debug "Saved #{orderitems.length} orders and #{products.length} products."

# Assigns missing OrderIDs and IDs
fixData = ({ orders, inventory }) ->
  console.debug "Fixing data..."
  orderitems = products = null
  Promise.resolve(orders)
    .then (orders) -> new OrderItem(o) for o in orders
    .then fixMissingOrderIDs
    .then fixMissingIDs
    .then (results) -> orderitems = results
    .then -> new Product(p) for p in inventory
    .then (results) -> products = results
    .then -> { orderitems, products }

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
  getAuthToken()
    .then -> Promise.all([getSpreadsheetID(), getLastSyncedTime()])
    .then (params) -> getSpreadsheetData(params...)

# Database section
db = null
openDB = new Promise (resolve, reject) ->
  migrations = [
    (e) ->
      { result } = e
      os = result.createObjectStore 'orders', keyPath: 'order_id', autoIncrement: true
      os.createIndex 'customer', 'customer', unique: false
      os.createIndex 'status', 'status', unique: false
      os.createIndex 'hold_until', 'hold_until', unique: false
      os.createIndex 'delivery_location', 'delivery_location', unique: false
      os.createIndex 'date_sold', 'date_sold', unique: false
      os.createIndex 'price', 'price', unique: false
      os.createIndex 'comment', 'comment', unique: false
      os.createIndex 'updated', 'updated', unique: false
      os = result.createObjectStore 'orderitems', keyPath: 'id', autoIncrement: true
      os.createIndex 'customer', 'customer', unique: false
      os.createIndex 'order_id', 'order_id', unique: false
      os.createIndex 'product', 'product', unique: false
      os.createIndex 'qty', 'qty', unique: false
      os.createIndex 'weight', 'weight', unique: false
      os.createIndex 'price', 'price', unique: false
      os.createIndex 'status', 'status', unique: false
      os.createIndex 'comment', 'comment', unique: false
      os.createIndex 'hold_until', 'hold_until', unique: false
      os.createIndex 'delivery_location', 'delivery_location', unique: false
      os.createIndex 'date_sold', 'date_sold', unique: false
      os.createIndex 'updated', 'updated', unique: false
      os = result.createObjectStore 'products', keyPath: 'product'
      os.createIndex 'type', 'type', unique: false
      os.createIndex 'total', 'total', unique: false
      os.createIndex 'available', 'available', unique: false
      os.createIndex 'price', "price", unique: false
      os.createIndex 'units', "units", unique: false
      os.createIndex 'comment', "comment", unique: false
      os.createIndex 'updated', "updated", unique: false
      os = result.createObjectStore 'changes'
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
getAuthToken = oauth2rizer(GOOGLE)
Stockman.getAuthToken = getAuthToken

# Gets a function which can execute the given Apps Script function remotely
executeAppsScriptFunction = (functionName) ->
  sanitize = (params) ->
    return params unless typeof params is 'object'
    return params.toISOString() if params instanceof Date
    return params.map(sanitize) if params instanceof Array
    result = {}
    result[sanitize(k)] = sanitize(v) for own k, v of params
    result

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
      data.parameters = sanitize(parameters)
      method = 'post'
      post = (token) ->
        method = 'post'
        headers = { Authorization: "Bearer #{token}" }
        data = JSON.stringify(data)
        console.debug data
        ajax.request({ method, url, headers, data, handlers })
      getAuthToken().then(post)

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
  applicationCache.addEventListener event, applicationCacheHandler

console.log "Welcome to stockman v#{VERSION}"
start()

router = (event) ->
  { oldURL, newURL } = event
  url = new URL(newURL)
  { pathname, hash } = url
  switch hash
    when '#dashboard' then renderDashboard()
    when '#settings'  then renderSettings()
    when '#orders'    then renderOrders()
    when '#inventory' then renderInventory()

addEventListener 'hashchange', router

addEventListener 'online', ->
  getUI.then (ui) ->
    ui.replaceClass('body')('offline')('online')
    setTimeout((-> ui.removeClass('body')('online')), 5000)
addEventListener 'offline', ->
  getUI.then (ui) ->
    ui.replaceClass('body')('online')('offline')

getUI.then (ui) ->
  ui.listen('#choose-spreadsheet')('change', 'submit') spreadsheetHandler

@Stockman = Stockman
@p = console.debug.bind(console)
