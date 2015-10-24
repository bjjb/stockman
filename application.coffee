"use strict"

VERSION = 1
WORKSHEETSFEED = "http://schemas.google.com/spreadsheets/2006#worksheetsfeed"
CELLSFEED      = "http://schemas.google.com/spreadsheets/2006#cellsfeed"
LISTFEED       = "http://schemas.google.com/spreadsheets/2006#listfeed"

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
  post: (url) ->
    load = -> JSON.parse(@responseText)
    (data) ->
      request('post', url, { Authorization: "Bearer: #{token}" }, data, { load })

rejolve = (x) -> Promise[x? and 'resolve' or 'reject'](x)
urlencode = (o) -> ([k, v].map(encodeURIComponent).join('=') for own k, v of o).join('&')
taskChain = (tasks) -> tasks.reduce ((p, t) -> p.then(t)), Promise.resolve()
arrayify = (obj) -> x for x in obj # !!arrayify(arguments) instanceof Array //=> true
serializeXML = (xml) -> xml.documentElement.innerHTML
deserializeXML = (s,t) -> x = document.createElement(t ? 'feed'); x.innerHTML = s; x
apply = (f) -> (a...) -> (o) -> o[f](a...) # apply('toLowerCase')()("BOO!") //=> "boo!" 
utils = { rejolve, urlencode, ajax, taskChain, arrayify, serializeXML, deserializeXML }

CREDENTIALS =
  client_id: "882209763081-p97bm2pb8egcmsttkkssceda5mqqsnkg.apps.googleusercontent.com",
  client_secret: "5YDG6-ezoZv04_8SXkjcrizf",
  auth_uri: "https://accounts.google.com/o/oauth2/auth",
  token_uri: "https://www.googleapis.com/oauth2/v3/token"
  scopes: [ 'https://spreadsheets.google.com/feeds' ]
  redirect_uri: "#{location.protocol}//#{location.host}"

Debugger = (prefix = "DEBUG") ->
  owner = @
  (args...) ->
    message = args.join(" ")
    console.debug(Error("#{prefix}: #{message}"), "this:", @)

Inventory = (ss, db) ->
  sync = ->
    throw "SYNC INVENTORY"
  { sync }

Orders = (ss, db) ->
  debug = Debugger("Orders:")
  sync = ->
    debug("sync...")
    db.replace('orders', ss.orders())
  { sync }

# SpreadSheet interface
SS = (ui) ->
  debug = Debugger("SS:")
  auth = oauth2rizer(CREDENTIALS)
  googleSheets = ->
    rewrite = (url) -> "/google-sheets/#{url}"
    auth().then (token) ->
      GoogleSheets({ token, rewrite })
  script = (id) ->
    body = JSON.stringify({ function: 'getOrders', parameters: [], devMode: true })
    ajax.post("https://script.googleapis/v1/scripts/#{id}:run")(script).then ->
      console.log response
  spreadsheet = ->
    debug("spreadsheet()")
    return Promise.resolve(sessionStorage.spreadsheet) if sessionStorage.spreadsheet?
    return get(localStorage.spreadsheet) if localStorage.spreadsheet?
    chooseSS().then(get)
  worksheets = ->
    debug("worksheets()")
    spreadsheet().then(getWorksheetsURL).then(get).then (worksheets) ->
      results = for e in worksheets.querySelectorAll('entry')
        id: e.querySelector('id').innerHTML
        title: e.querySelector('title').innerHTML
        cells: e.querySelector("link[rel='#{CELLSFEED}']").getAttribute('href')
        list: e.querySelector("link[rel='#{LISTFEED}']").getAttribute('href')
      results.reduce(((m, o) -> m[o.title] = o; m), {})
  worksheet = (name) ->
    debug("worksheet(#{name})")
    return get(localStorage[name]) if localStorage[name]?
    worksheets().then (worksheets) ->
      get(worksheets[name].cells).then (feed) ->
        console.debug "Got the cells! Now what?!", feed
        Promise.reject "OK"
  parse = (xml) ->
    console.debug("Parsing XML", xml)
    result = xml2json.xml_to_object(xml.innerHTML)
    console.debug(result)
    result
  orders = ->
    worksheet('ORDERS').then(parse).then (rows) ->
      new Order(row) for row in rows
  spreadsheets = ->
    index().then (doc) ->
      for entry in doc.querySelectorAll('entry')
        title: entry.querySelector('title').innerHTML
        id: entry.querySelector('id').innerHTML
  cache = (key, f) ->
    if sessionStorage[key]?
      Promise.resolve(deserializeXML(sessionStorage[key]))
    else
      f().then (xml) ->
        sessionStorage[key] = serializeXML(xml)
        xml
  index = ->
    cache 'spreadsheets', -> googleSheets().then(apply('index')(projection: 'basic'))
  get = (id) ->
    throw "Invalid ID: #{id}" unless typeof id is 'string'
    cache id, -> googleSheets().then(apply('get')(id))
  chooseSS = ->
    debug("chooseSS()")
    ui.chooseSS(spreadsheets, checkSpreadsheet).then (spreadsheet) ->
      localStorage.spreadsheet = spreadsheet
  getCellsFeedURL = (worksheet) ->
    Promise.resolve(spreadsheet.querySelector("link[rel='#{CELLSFEED}']").getAttribute('href'))
  getListFeedURL = (worksheet) ->
    Promise.resolve(spreadsheet.querySelector("link[rel='#{LISTFEED}']").getAttribute('href'))
  getWorksheetsURL = (spreadsheet) ->
    Promise.resolve(spreadsheet.querySelector("link[rel='#{WORKSHEETSFEED}']").getAttribute('href'))
  checkWorksheets = (worksheets) ->
    new Promise (resolve, reject) ->
      results = []
      for e in worksheets.querySelectorAll('entry')
        results.push
          id: e.querySelector('id').innerHTML
          title: e.querySelector('title').innerHTML
          links: for link in e.querySelectorAll('link')
            rel: link.getAttribute('rel')
            href: link.getAttribute('href')
      titles = (w.title for w in results)
      console.log "All titles: #{titles}"
      return reject() unless 'ORDERS' in titles and 'INVENTORY' in titles
      resolve(results)
  checkSpreadsheet = (id) ->
    get(id).then(getWorksheetsURL).then(get).then(checkWorksheets)
  parse = (doc) ->
    Promise.reject "Parse data is not implemented"
  objects = (worksheet) ->
    getSheet(worksheet).then(parse)
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
  $       = (q) => document.querySelector(q)
  $$      = (q) => e for e in document.querySelectorAll(q)
  goto    = (q) => location.hash = q
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
  debug = Debugger("UI:")
  listen = (q) -> (event) -> (callback) -> $(q).addEventListener event, callback
  ignore = (q) -> (event) -> (callback) -> $(q).removeEventListener event, callback
  fatal = ->
    $('.fatal.alert .message').innerHTML = error.message
    show('.fatal.alert')
  sync = (f) ->
    success = ->
      $('.alert.synchronizing .message').innerHTML = 'Synchronized!'
      hide('.alert.synchronizing .spinner')
      $('.alert.synchronizing').classList.remove('alert-info')
      $('.alert.synchronizing').classList.add('alert-success')
      setTimeout (-> hide('.alert.synchronizing')), 5000
    error = (error) ->
      $('.alert.synchronizing .message').innerHTML = "Failed to synchronize!<br>#{error}"
      hide('.alert.synchronizing .spinner')
      $('.alert.synchronizing').classList.remove('alert-info')
      $('.alert.synchronizing').classList.add('alert-danger')
      setTimeout (-> ui.hide('.alert.synchronizing')), 5000
      throw error
    $('.alert.synchronizing .message').innerHTML = 'Synchronizing...'
    show('.alert.synchronizing .spinner')
    $('.alert.synchronizing').classList.add('alert-info')
    $('.alert.synchronizing').classList.remove('alert-success')
    $('.alert.synchronizing').classList.remove('alert-danger')
    show('.alert.synchronizing')
    f().then(success, error)
  chooseSS = (spreadsheets, check) ->
    new Promise (resolve) ->
      init = ->
        debug("chooseSS.init")
        disable('#choose-ss select')
        $('#choose-ss .help-block').innerHTML = "Stockman is loading a list of your spreadsheets"
        show('#choose-ss .spinner')
        goto('#choose-ss')
        listen('#choose-ss select')('change')(change)
        listen('#choose-ss form')('submit')(submit)
      start = (options) ->
        text = "Choose a spreadsheets with INVENTORY and ORDERS"
        render('#choose-ss select')(spreadsheets: options)
        $('#choose-ss .help-block').innerHTML = text
        hide('#choose-ss .spinner')
        enable('#choose-ss select')
      change = (event) ->
        disable('#choose-ss select')
        show('#choose-ss .spinner')
        $('#choose-ss .form-group').classList.remove('has-success')
        $('#choose-ss .form-group').classList.remove('has-error')
        $('#choose-ss .help-block').innerHTML = "Checking..."
        check(@value).then(valid, invalid)
      valid = ->
        text = "... is a valid stockman spreadsheet!"
        $('#choose-ss .form-group').classList.remove('has-error')
        $('#choose-ss .form-group').classList.add('has-success')
        $('#choose-ss .help-block').innerHTML = text
        hide('#choose-ss .spinner')
        enable('#choose-ss select')
        enable('#choose-ss button[type=submit]')
      invalid = ->
        text = "... is <strong>not</strong> a valid stockman spreadsheet."
        disable('#choose-ss button[type=submit]')
        enable('#choose-ss select')
        hide('#choose-ss .spinner')
        $('#choose-ss .form-group').classList.remove('has-success')
        $('#choose-ss .form-group').classList.add('has-error')
        $('#choose-ss .help-block').innerHTML = text
      submit = (event) ->
        event.preventDefault()
        ignore('#choose-ss form')('submit')(submit)
        ignore('#choose-ss select')('change')(change)
        disable('#choose-ss select')
        disable('#choose-ss form')
        resolve @ss.value
      Promise.resolve().then(init).then(spreadsheets).then(start)
  {$, $$, goto, show, hide, enable, disable, render, fatal, sync, chooseSS }

Changes = (ui) ->
  
Stockman = (event) ->
  ui = UI()
  ss = SS(ui)
  db = DB(ui, ss)
  orders = Orders(ss, db, ui)
  inventory = Inventory(ss, db, ui)
  changes = Changes()
  debug = Debugger("Stockman:")
  sync = ->
    ui.sync ->
      Promise.all [orders.sync(), inventory.sync()]
  offline = ->
    ui.show('.alert.offline')
  online = ->
    ui.hide('.alert.offline')
    setTimeout (-> ui.hide('.alert.online')), 5000
  start = ->
    console.log "Welcome to Stockman v#{VERSION}"
    sync().then -> ui.goto('#orders')
  fatal = (error) ->
    ui.fatal(error.message)
    throw new Error(error)
  offline() unless @navigator.onLine
  @addEventListener 'online', online
  @addEventListener 'offline', offline
  @stockman = { ui, db, ss }
  start()

Stockman.UI = UI
Stockman.SS = SS
Stockman.DB = DB
Stockman.Changes = Changes
Stockman.Orders = Orders
Stockman.Inventory = Inventory
Stockman.VERSION = VERSION
Stockman.utils = utils

GoogleAppScripts = ->
  auth = -> oauth2rizer(CREDENTIALS)
  handlers = { 'load'
  post = (url) -> (data) -> (token) -> ajax.post('post', url, data, { Authorization: "Bearer #{token}" }, handlers)
  run  = (script) -> auth().then(post(url)(script))
addEventListener 'load', Stockman
@Stockman = Stockman
