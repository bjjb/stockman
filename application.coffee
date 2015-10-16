console.log "Welcome to Stockman"

VERSION = 1

ordersLinkClicked = (event) ->
inventoryLinkClicked = (event) ->
refreshLinkClicked = (event) ->

# Handles events in the entire #orders lists
handleOrdersClick = (event) ->
  { target } = event
  if 'action' in target.classList
    return sellOrderItem(event) if target.nodeName is 'SPAN'
    return changeOrderItemAction(event) if target.nodeName is 'A'
    return performOrderItemAction(event) if target.nodeName is 'BUTTON'

# Handles submit events in the entire #orders lists
handleOrdersSubmit = (event) ->
  { target } = event
  return sellOrderItem(event) if target.name is 'price'

# Change the action that will be performed by the button
changeOrderItemAction = (event) ->
  { target } = event
  event.preventDefault()
  action = target.innerText
  klass = { Sell: 'btn-success', Cancel: 'btn-danger', Hold: 'btn-info', Short: 'btn-warning' }
  btnGroup = target.parentElement
  btnGroup = btnGroup.parentElement until 'btn-group' in btnGroup.classList
  for e in btnGroup.querySelectorAll('.btn')
    e.classList.remove(c) for c in e.classList when c?.match(/^btn-/)
    e.classList.add(klass[action])
  button = btnGroup.querySelector('.btn')
  button.innerText = target.innerText
  button.dataset.action = target.innerText

# Perform an action on an order item
performOrderItemAction = (event) ->
  { target } = event
  { dataset: { action } } = target
  switch action
    when 'Sell' then sellingOrderItem(event)
    when 'Hold' then holdOrderItem(event)
    when 'Short' then shortOrderItem(event)
    when 'Cancel' then cancelOrderItem(event)
    else console.error("Unknown action: #{action}", event)

# Start selling an order item - need to enter the price
sellingOrderItem = (event) ->
  { target } = event
  orderItem = target.parentElement
  orderItem = orderItem.parentElement until 'order-item' in orderItem.classList
  orderItem.querySelector('.actions').hidden = true
  orderItem.querySelector('.price').hidden = false

# Sell an order item - reduce the inventory, add the price to the order total
sellOrderItem = (event) ->
  { target } = event
  event.preventDefault()
  orderItem = target.parentElement
  orderItem = orderItem.parentElement until 'order-item' in orderItem.classList
  price = orderItem.querySelector('input[name="price"]')
  order = orderItem.parentElement
  order = order.parentElement until 'order' in order.classList
  total = order.querySelector('.total')
  total.innerText = Number((total.innerText or 0.0)) + Number(price.value)
  price.value = ''
  quantity = orderItem.querySelector('.quantity')
  quantity.innerText = Number(quantity.innerText) - 1
  orderItem.querySelector('.price').hidden = true
  orderItem.querySelector('.actions').hidden = false

setOrderItemAction = (event) ->
  console.log event

filterMarketDayOrders = ($event) ->
  q = $(@).val()
  m = new RegExp(q, 'i')
  $('#marketday #orders .order').each (order) ->
    $(@).attr "hidden", ->
      not $('a.customer', @).html().match(m)

saveProduct = (product) ->
  new Promise (resolve, reject) ->
    openDB.then (db) ->
      transaction = db.transaction('inventory', 'readwrite')
        .objectStore('products')
        .add(product)
      transaction.onsuccess = resolve
      transaction.onerror = reject

# = jQuery plugins

# Inserts products and applies behaviour to the jQueries
$.fn.products = (products) ->
  productTemplate = $("#product-template").html()
  render = (product) ->
    Mustache.render(productTemplate, new Product(product))
  renderAll = (products) ->
    products.map(render).join("\n")
  newProduct = ->
    $('#new-product-modal').modal()
  createProduct = ->
    console.debug "createProduct"
    product = $("#new-product-name").val()
    price = Number($("#new-product-price").val())
    units = $("#new-product-units").val() or "-"
    type = $("#new-product-type").val()
    product = new Product({ type, product, price, units })
    openDB.then (db) ->
      transaction = db.transaction('products', 'readwrite')
      transaction.oncomplete = (event) ->
        $('#new-product-form').find('input', 'textarea', 'select').val('')
        $('#products tbody').append(render(product))
        $('#new-product-modal').modal('hide')
      transaction.onfailure = (event) ->
        console.error event
        alert("Failed to save product")
      objectStore = transaction.objectStore('products')
      request = objectStore.add(product)
      request.onsuccess = -> console.debug "Added product", product
  editProduct = ->
    console.debug "editProduct"
  updateProduct = ->
    console.debug "updateProduct"
  deleteProduct = ->
    console.debug "deleteProduct"
  setNewProductUnits = ->
    $('#new-product-units').val($(@).html()[1..-1])
    $('#new-product-form span.units').html($(@).html())
  Promise.resolve(products?() or products).then (products) =>
    $('tbody', @).html -> products.map(render).join("\n")
    $('button.new-product').on 'click', newProduct
    $('#new-product-form a.unit').on 'click', setNewProductUnits
    $('#new-product-form').on 'submit', createProduct
    $('button.edit-product').on 'click', editProduct
    $('form.update-product').on 'submit', updateProduct
    $('button.delete-product').on 'click', deleteProduct

class Product
  @html = (product, template = "#product-template") ->
    return product.map(@html).join("\n") if product instanceof Array
    Mustache.render $(template).html(), product
  constructor: ({ @product, @type, @price, @units }) ->
    @units ?= '-'
  pricePer: -> "$#{Number(@price).toFixed(2)} /#{@units}"
  types: -> [ 'Beef', 'Chicken', 'Sauces', 'Pork', 'Sausage', 'Other' ]

class Order
  constructor: ({ @id, @customer, @items, @comment, @total, @status, @placedOn, @holdUntil, @location }) ->
    (item.id ?= n) for item, n in @items
    @items = (new Order.Item(item) for item in @items)
    @total ?= 0.0
    @location ?= 'Market'
  context: ->
    switch @status
      when 'Open' then 'success'
      when 'Cancelled' then 'danger'
      when 'Closed' then 'default'
      when 'Short' then 'warning'
      else 'info'

Order.new = (obj) -> new Order(obj)

class Order.Item
  constructor: ({ @product, @quantity, @comment, @status, @weight, @price }) ->
  $: -> $("#order-item-#{@id}")
  template: -> @_template ?= $('#order-item-template').html()
  context: ->
    switch @state
      when 'SOLD' then 'success'
      when 'ORDERED' then 'default'
      when 'SHORT' then 'warning'
      when 'OPEN' then 'primary'
  actions: ->
    switch @state
      when 'OPEN' then ['Sell', 'Hold', 'Short', 'Cancel']
      when 'SOLD' then ['Close', 'Undo']
      when 'CLOSED' then ['Undo']
      else console.error "Unknown state #{@state} for", @


fetchTypes = ->
  console.debug "Fetching types"
  Promise.resolve [
    { type: 'Beef' }
    { type: 'Chicken' }
    { type: 'Sauces' }
    { type: 'Pork' }
    { type: 'Sausages' }
    { type: 'Other' }
  ]

fetchProducts =  ->
  console.debug "Fetching products"
  Promise.resolve [
    { product: 'Ham Hock', price: 6.5, units: 'lb', type: 'Pork' }
    { product: 'SCC', price: 6.5, units: 'lb', type: 'Chicken' }
    { product: 'Whole chicken', price: 7.5, units: '-', type: 'Chicken' }
    { product: 'Breakfast Sausage', price: 6, type: 'Pork' }
  ]

fetchInventory = ->
  console.debug "Fetching inventory"
  Promise.resolve [
    { product: 'Ham Hock', quantity: 4, price: 6.75 },
    { product: 'SCC', quantity: 11, price: 5.50 },
    { product: 'Whole Chicken', quantity: 5, price: 7.5 }
  ]

fetchOrders = ->
  console.debug "Fetching orders"
  Promise.resolve [
    { id: 1, customer: "Adam Anderson", items: [ { product: 'Ham Hock', quantity: 2 }, { product: 'SCC', quantity: 4 } ], comment: 'Has coffee' }
    { id: 2, customer: "Bob Belcher",   items: [ { product: 'Whole Chicken', quantity: 1, comment: 'Biggest available' } ] }
  ]

fetchRemoteData = ->
  console.debug "Fetching remote data..."
  data = {}
  fetchTypes()
    .then (types) -> data.types = types
    .then -> fetchProducts()
    .then (products) -> data.products = products
    .then fetchInventory
    .then (inventory) -> data.inventory = inventory
    .then fetchOrders
    .then (orders) -> data.orders = orders
    .then -> data

openDB = new Promise (resolve, reject) ->
  fetchRemoteData().then (remoteData) ->
    op = indexedDB.open('stockman', VERSION)
    op.onsuccess = (event) ->
      console.debug "openDB SUCCESS"
      resolve(event.target.result)
    op.onerror = (event) ->
      console.debug "openDB ERROR"
      reject(event)
    op.onupgradeneeded = (event) ->
      console.debug "openDB UPGRADE NEEDED", event
      db = event.target.result
      db.createObjectStore('products', keyPath: 'product')
      db.createObjectStore('inventory', keyPath: 'product')
      db.createObjectStore('orders', keyPath: 'id')
      request = db.createObjectStore('types', keyPath: 'type')
      request.transaction.oncomplete = ->
        transaction = db.transaction(['products', 'orders', 'inventory', 'types'], 'readwrite')
        store = transaction.objectStore('products')
        store.add product for product in remoteData.products
        store = transaction.objectStore('inventory')
        store.add entry for entry in remoteData.inventory
        store = transaction.objectStore('orders')
        store.add order for order in remoteData.orders
        store = transaction.objectStore('types')
        store.add type for type in remoteData.types
        Product.types = types

allProducts = ->
  new Promise (resolve, reject) ->
    products = []
    openDB.then (db) ->
      op = db.transaction('products').objectStore('products').openCursor()
      op.onsuccess = (event) ->
        cursor = event.target.result
        return resolve(products) unless cursor
        products.push cursor.value
        cursor.continue()
      op.onerror = reject

$ ->
  $('#products .products').products(allProducts)
  return
  $('#inventory .inventory').inventory(allInventory)
  $('#orders .orders').orders(allOrders)
  $('#marketday .inventory').inventory(marketdayInventory)
  $('#marketday .orders').orders(marketdayOrders)
