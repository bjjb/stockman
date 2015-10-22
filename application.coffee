"use strict"

VERSION = 1
ajax =
  handle: (handlers = {}) -> (e) -> handlers[@status]?(e)
  request: ({ method, url, headers, data, handlers }) ->
    headers ?= {}
    handlers ?= {}
    data = utils.urlencode(data) if typeof data is 'object'
    new Promise (resolve, reject) ->
      xhr = new XMLHttpRequest
      xhr.open(method, url)
      xhr.addHeader(k, v) for own k, v of headers
      xhr.addEventListener(k, v) for own k, v of handlers
      xhr.send(data)

rejolve = (x) -> Promise[x? and 'resolve' or 'reject'](x)
urlencode = (o) -> ([k, v].map(encodeURIComponent).join('=') for own k, v of o).join('&')
taskChain = (tasks) -> tasks.reduce ((p, t) -> p.then(t)), Promise.resolve()
utils = { rejolve, urlencode, ajax, taskChain }

saveProduct = (product) ->
  new Promise (resolve, reject) ->
    openDB().then (db) ->
      transaction = db.transaction('inventory', 'readwrite')
        .objectStore('products')
        .add(product)
      transaction.onsuccess = resolve
      transaction.onerror = reject

Product = ({ @product, @total, @held, @open, @available, @comment, @price, @units }) ->

Order = ({ @id, @customer, @items, @comment, @total, @status, @placedOn, @holdUntil, @location }) ->

OrderItem = ({ @product, @quantity, @comment, @status, @weight, @price }) ->

DUMMUDATA =
  inventory: [
    { product: 'Ham Hock', quantity: 4, price: 6.75 },
    { product: 'SCC', quantity: 11, price: 5.50 },
    { product: 'Whole Chicken', quantity: 5, price: 7.5 }
  ]
  orders: [
    { id: 1, customer: "Adam Anderson", items: [ { product: 'Ham Hock', quantity: 2 }, { product: 'SCC', quantity: 4 } ], comment: 'Has coffee' }
    { id: 2, customer: "Bob Belcher",   items: [ { product: 'Whole Chicken', quantity: 1, comment: 'Biggest available' } ] }
  ]

CREDENTIALS =
  client_id: "882209763081-417l7db84s429rg541idqin8gm0arham.apps.googleusercontent.com",
  client_secret: "WMJoSo1W-awHOG6lsQR3BVxf",
  auth_uri: "https://accounts.google.com/o/oauth2/auth",
  token_uri: "https://www.googleapis.com/oauth2/v3/token"
  scopes: [ 'https://spreadsheets.google.com/feeds' ]
  redirect_uri: "#{location.protocol}//#{location.host}/oath2"

Inventory = (backend) ->
  clear = -> backend.clear('inventory')
  replace = (source) ->
    clear().then(source.all).then (objects) ->
      objects.reduce ((p, object) -> p.then(-> insert(object))), Promise.resolve()
  all = ->
    backend.objects('inventory').then (products) ->
      products.map (product) ->
        console.debug "new Product", product
        new Product(product)
  { replace, all }

Orders = (backend) ->
  clear = -> backend.clear('orders')
  replace = (source) ->
    clear().then(source.all).then (objects) ->
      objects.reduce ((p, object) -> p.then(-> insert(object))), Promise.resolve()
  all = ->
    backend.objects('orders').then (orderItems) ->
      orderItems.map (orderItem) ->
        console.debug "new OrderItem", orderItem
        new OrderItem(orderItem)
  { replace, all }

# SpreadSheet interface
SS = (ui) ->
  Document = (doc) ->
    entries = -> doc.querySelectorAll('entry')
    links   = -> doc.querySelectorAll('link')
    worksheetsfeed = -> links.w
    { worksheetsfeed }
  auth = oauth2rizer(CREDENTIALS)
  googleSheets = ->
    rewrite = (url) -> "/google-sheets/#{url}"
    auth().then (token) -> GoogleSheets({ token, rewrite })
  index = ->
    googleSheets().then (googleSheets) ->
      googleSheets.index().then (doc) ->
        results = []
        for entry in doc.querySelectorAll('entry')
          results.push
            title: entry.querySelector('title').innerHTML
            id: entry.querySelector('id').innerHTML
        results
  get = (id) ->
    throw "Invalid ID: #{id}" unless typeof id is 'string'
    googleSheets().then (googleSheets) ->
      googleSheets.get(id)
  choose = -> # triggers the choose spreadsheet flow
    ui.$('#choose-ss .help-block').innerHTML = "Stockman is loading a list of your spreadsheets"
    ui.disable('#choose-ss select')
    ui.show('#choose-ss .spinner')
    ui.goto('#choose-ss')
    index().then(chooseSS)
  parseData = (doc) ->
    console.debug "WORKING HERE", doc
    Promise.reject "Parse data is not implemented"
  objects = (worksheet) ->
    console.debug "Getting all objects on #{worksheet}"
    Promise.reject("Not done")
  chooseSS = (options) -> # called with the spreadsheets [ { id, title } ]
    new Promise (resolve, reject) ->
      changed = (e) ->
        ui.disable('#choose-ss button[type=submit]')
        check = (spreadsheet_url) => # check the spreadsheet with this ID
          get(spreadsheet_url).then (doc) -> # get the XML
            worksheets_url = doc.querySelector('link[rel="http://schemas.google.com/spreadsheets/2006#worksheetsfeed"]').getAttribute('href')
            get(worksheets_url).then (doc) -> # get the worksheets feed
              title = doc.querySelector('title').innerHTML
              titles = (e.innerHTML.toLowerCase() for e in doc.querySelectorAll('entry title'))
              return Promise.reject(title) unless 'inventory' in titles and 'orders' in titles
              results = { spreadsheet: spreadsheet_url, worksheets: worksheets_url }
              for e in doc.querySelectorAll('entry')
                if (title = e.querySelector('title').innerHTML.toLowerCase) in ['inventory', 'orders']
                  results[title] = e.querySelector('id').innerHTML
              Promise.resolve(results) # resolves to [{id, title}] of worksheets
        valid = (values) =>
          select = @
          done = ->
            event.preventDefault()
            select.removeEventListener 'change', changed
            @removeEventListener 'submit', done
            localStorage[k] = v for own k, v of values
            resolve(localStorage.spreadsheet) # DONE!
          ui.enable('#choose-ss select')
          ui.hide('#choose-ss .spinner')
          ui.$('#choose-ss .form-group').classList.remove('has-error')
          ui.$('#choose-ss .form-group').classList.add('has-success')
          ui.$('#choose-ss .help-block').innerHTML = "... is a valid stockman spreadsheet!"
          ui.$('#choose-ss form').addEventListener 'submit', done
          ui.enable('#choose-ss button[type=submit]')
        invalid = (title) =>
          ui.enable('#choose-ss select')
          ui.hide('#choose-ss .spinner')
          ui.$('#choose-ss .form-group').classList.remove('has-success')
          ui.$('#choose-ss .form-group').classList.add('has-error')
          ui.$('#choose-ss .help-block').innerHTML = "<em>#{title}</em> is not a valid stockman spreadsheet"
        ui.disable('#choose-ss select')
        ui.show('#choose-ss .spinner')
        ui.$('#choose-ss .help-block').innerHTML = "Checking..."
        check(@value).then valid, invalid
      ui.render('#choose-ss select')(spreadsheets: options)
      ui.$('#choose-ss select').addEventListener 'change', changed
      ui.$('#choose-ss .help-block').innerHTML = "Choose a spreadsheet with INVENTORY and ORDERS"
      ui.hide('#choose-ss .spinner')
      ui.enable('#choose-ss select')
  inventory = Inventory({ objects })
  orders    = Orders({ objects })
  { inventory, orders }

# DataBase interface
DB = (ui, ss) ->
  MIGRATIONS = [
    ->
      @createObjectStore('inventory', keyPath: 'product')
      @createObjectStore('orders', autoincrement: true)
  ]
  openDB = ->
    new Promise (resolve, reject) ->
      success = -> resolve @result
      error = (error) ->
        ui.$('.alert.fatal').innerHTML = "Failed to open database!"
        ui.show('.alert.fatal')
        console.error(error)
        reject(error)
      upgrade = (event) ->
        { oldVersion, newVersion } = event
        migrations = MIGRATIONS[oldVersion..newVersion]
        utils.taskChain(migrations.map((m) -> m.bind(event.target.result)))
      request = indexedDB.open('stockman', VERSION)
      request.addEventListener 'success', success
      request.addEventListener 'error', error
      request.addEventListener 'upgradeneeded', upgrade
  clear = (store) ->
    new Promise (resolve, reject) ->
      error = (e) ->
        console.error(e, @)
        reject e
      openDB().then (db) ->
        transaction = db.transaction([store], 'readwrite')
        transaction.addEventListener 'error', error
        store = transaction.objectStore(store)
        request = store.clear()
        request.addEventListener 'success', resolve
        request.addEventListener 'error', reject
  orders = Orders({ clear })
  inventory = Inventory({ clear })
  { orders, inventory, clear }

UI = ->
  $       = (q) => @document.querySelector(q)
  $$      = (q) => e for e in @document.querySelectorAll(q)
  goto    = (q) => @location.hash = q
  show    = (q) -> e.hidden = false for e in $$(q)
  hide    = (q) -> e.hidden = true for e in $$(q)
  enable  = (q) -> e.disabled = false for e in $$(q)
  disable = (q) -> e.disabled = true for e in $$(q)
  render  = (q) ->
    partials = (k) -> $(k).innerHTML or throw "Partial template missing: #{k}"
    (view) ->
      Promise.resolve $$(q).forEach (e) ->
        return console.error("No template", e) unless t = e.dataset.template
        return console.error("Template missing", t) unless t = $(t)?.innerHTML
        e.innerHTML = Mustache.render(t, view, partials)
  {$, $$, goto, show, hide, enable, disable, render }

Stockman = (event) ->
  ui = UI.call(@)
  ss = SS.call(@, ui)
  db = DB.call(@, ui, ss)
  changes =
    push: -> Promise.reject("changes.push not implemented")
  sync = ->
    success = ->
      ui.$('.alert.synchronizing .message').innerHTML = 'Synchronized!'
      ui.hide('.alert.synchronizing .spinner')
      ui.$('.alert.synchronizing').classList.remove('alert-info')
      ui.$('.alert.synchronizing').classList.add('alert-success')
      setTimeout (-> ui.hide('.alert.synchronizing')), 5000
    error = (error) ->
      console.error(error)
      ui.$('.alert.synchronizing .message').innerHTML = "Failed to synchronize!<br>#{error}"
      ui.hide('.alert.synchronizing .spinner')
      ui.$('.alert.synchronizing').classList.remove('alert-info')
      ui.$('.alert.synchronizing').classList.add('alert-danger')
      setTimeout (-> ui.hide('.alert.synchronizing')), 5000
    ui.$('.alert.synchronizing .message').innerHTML = 'Synchronizing...'
    ui.show('.alert.synchronizing .spinner')
    ui.$('.alert.synchronizing').classList.add('alert-info')
    ui.$('.alert.synchronizing').classList.remove('alert-success')
    ui.$('.alert.synchronizing').classList.remove('alert-danger')
    ui.show('.alert.synchronizing')
    utils.taskChain([ db.orders.replace(ss.orders), db.inventory.replace(ss.inventory) ])
      .then -> changes.push(ss)
      .then(success).catch(error)
  offline = ->
    ui.show('.alert.offline')
  online = ->
    ui.hide('.alert.offline')
    setTimeout (-> ui.hide('.alert.online')), 5000
  start = ->
    console.log "Welcome to Stockman v#{VERSION}"
    sync().then -> ui.goto('#orders')
  fatal = (error) ->
    ui.$('.fatal.alert .message').innerHTML = error.message
    ui.show('.fatal.alert')
    throw(error)
  offline() unless @navigator.onLine
  @addEventListener 'online', online
  @addEventListener 'offline', offline
  @stockman = { ui, db, ss }
  start()

Stockman.UI = UI
Stockman.SS = SS
Stockman.DB = DB
Stockman.VERSION = VERSION
Stockman.utils = utils

addEventListener 'load', Stockman
@Stockman = Stockman
