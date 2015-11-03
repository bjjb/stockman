'use strict'
# MV*, a browser UI behaviour library.

MVStar = ({ document, location, history, Promise, Mustache, setTimeout, console, sync, authorize } = @) ->
  # DOM manipulation utilities
  $       = (q) => document.querySelector(q)
  $$      = (q) => e for e in document.querySelectorAll(q)
  goto    = (to) =>
    location.assign(to)
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
    (events...) ->
      (callbacks...) ->
          for q in qs
            for event in events
              for callback in callbacks
                e.removeEventListener(event, callback) for e in $$(q)
                e.addEventListener(event, callback)    for e in $$(q)
  ignore = (qs...) ->
    (events...) ->
      (callbacks...) ->
        for q in qs
          for event in events
            for callback in callbacks
              e.removeEventListener(event, callback) for e in $$(q)
  update = ({ orders, inventory }) ->
    render('#orders .panel-group.orders')({orders})
    render('#inventory tbody.products')({inventory})
    { orders, inventory }
  {$, $$, goto, show, hide, enable, disable, render, update, addClass,
    removeClass, replaceClass, listen, ignore }

@MVStar = MVStar
