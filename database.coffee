@Database = ->
  open('stockman').then ->
    orders: []
    inventory: []
    products: []
