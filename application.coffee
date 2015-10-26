"use strict"

VERSION = 1
GOOGLE =
  api_key: "AIzaSyDY9L74caWHWKwQt3v8PhUKJg1XrV1Sg1M"
  script_id: "MaUc2uQFRlN2zBkeCD7xP8qufI_6jYVb2"
  scripts_uri: "https://script.googleapis.com/v1/scripts"
  client_id: "882209763081-p97bm2pb8egcmsttkkssceda5mqqsnkg.apps.googleusercontent.com"
  client_secret: "5YDG6-ezoZv04_8SXkjcrizf"
  auth_uri: "https://accounts.google.com/o/oauth2/auth"
  token_uri: "https://www.googleapis.com/oauth2/v3/token"
  spreadsheet_id: "1hFU6T4UsSHaD8GMTpPEFMFcbQbHtsqX-jhQNXX-00bI" # TODO - make dynamic again
  scopes: [
    'https://spreadsheets.google.com/feeds',
    'https://www.googleapis.com/auth/spreadsheets'
  ]

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
utils = { rejolve, urlencode, ajax, taskChain, arrayify, serializeXML, deserializeXML }

Inventory = ({ui, backend}) ->
  replace = (inventory) ->
    items = inventory.items
  sync = ->
    backend.inventory(replace)
  { sync }

Order = (@data) ->
Product = (@data) ->
  
Orders = ({ui, backend}) ->
  replace = (orders) ->
    items = orders.items
  sync = ->
    backend.orders(replace)
  { sync }

UI = ({ document, location, Promise, Mustache, setTimeout, console, sync, authorize }) ->
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

  render  = (q) ->
    partials = (k) -> $(k).innerHTML or throw "Partial template missing: #{k}"
    (view) ->
      Promise.resolve $$(q).forEach (e) ->
        return console.error("No template", e) unless t = e.dataset.template
        return console.error("Template missing", t) unless t = $(t)?.innerHTML
        e.innerHTML = Mustache.render(t, view, partials)
  listen = (q) ->
    (event) ->
      (callback) ->
        $(q).removeEventListener(event, callback)
        $(q).addEventListener(event, callback)
  ignore = (q) -> (event) -> (callback) -> $(q).removeEventListener event, callback
  fatal = ->
    $('.fatal.alert .message').innerHTML = error.message
    show('.fatal.alert')
  sync = (f) ->
    success = ->
      replaceClass('.synchronizing')('working')('success')
      setTimeout((-> hide('.synchronizing')), 5000)
    error = (error) ->
      replaceClass('.synchronizing')('working')('error')
      throw error
    replaceClass('.synchronizing')('success', 'error')('working')
    show('.synchronizing')
    f().then(success, error)
  {$, $$, goto, show, hide, enable, disable, render, fatal, sync, authorize }

Changes = ({ ui }) ->

Backend = ({ ui, auth }) ->
  { script_id, scripts_uri } = GOOGLE
  post = (functionName, parameters = []) ->
    url = "#{scripts_uri}/#{script_id}:run"
    (token) ->
      new Promise (resolve, reject) ->
        method = 'post'
        devMode = true
        headers =
          Authorization: "Bearer #{token}"
        data = { parameters, devMode }
        data.function = functionName
        data = JSON.stringify(data)
        load = -> resolve(JSON.parse(@responseText).response.result)
        handlers = { load }
        ajax.request({method, url, headers, data, handlers})
  run = (functionName, parameters) -> auth().then(post(functionName, parameters))
  { spreadsheet_id } = GOOGLE
  getAllObjects = (force) ->
    new Promise (resolve, reject) ->
      { ORDERS, INVENTORY } = sessionStorage
      if ORDERS and INVENTORY and !force
        return resolve { ORDERS: JSON.parse(ORDERS), INVENTORY: JSON.parse(INVENTORY) }
      delete sessionStorage.access_token
      run('getAllObjects', [GOOGLE.spreadsheet_id]).then ({ORDERS, INVENTORY}) ->
        sessionStorage.ORDERS = JSON.stringify(ORDERS)
        sessionStorage.INVENTORY = JSON.stringify(INVENTORY)
        { ORDERS, INVENTORY }
  sync = ->
    getAllObjects().then ({ orders, inventory }) ->
      orders = (new Order(o) for o in orders)
      inventory = (new Product(p) for p in inventory)
      { orders, inventory }
  { run, sync, spreadsheet_id }

Stockman = (event) ->
  ui = UI(@)
  auth      = oauth2rizer(GOOGLE)
  backend   = Backend({ ui, auth })
  changes   = Changes({ ui })
  sync = ->
    ui.sync ->
      backend.sync()
  offline = ->
    ui.show('.alert.offline')
  online = ->
    ui.hide('.alert.offline')
    setTimeout (-> ui.hide('.alert.online')), 5000
  start = ->
    console.log "Welcome to Stockman v#{VERSION}"
    sync().then -> ui.goto('#inventory')
  fatal = (error) ->
    ui.fatal(error.message)
    throw new Error(error)
  offline() unless @navigator.onLine
  @addEventListener 'online', online
  @addEventListener 'offline', offline
  @stockman = { ui, backend, changes, sync, auth, orders, inventory }
  start()


Stockman.UI = UI
Stockman.Backend = Backend
Stockman.Changes = Changes
Stockman.Orders = Orders
Stockman.Inventory = Inventory
Stockman.VERSION = VERSION
Stockman.utils = utils

addEventListener 'load', Stockman
@Stockman = Stockman
