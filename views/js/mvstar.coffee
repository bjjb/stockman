'use strict'
# MV*, a browser UI behaviour library.

MVStar = ({ document, location, history, Element, Promise, Mustache, setTimeout, console } = @) ->
  # DOM manipulation utilities
  $ = (q) =>
    return q if q instanceof Element
    document.querySelector(q)

  $$ = (qs) =>
    return [qs] if qs instanceof Element
    e for e in document.querySelectorAll(qs)

  goto    = (to) =>
    location.assign(to)
    
  show = (qs...) -> (e.hidden = false for e in $$(q)) for q in qs

  hide = (qs...) -> (e.hidden = true for e in $$(q)) for q in qs

  enable = (qs...) -> (e.disabled = false for e in $$(q)) for q in qs
  
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
          (templates[t] ?= template(t)).then (t) ->
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

  ajax =
    request: (method, url) ->
      new Promise (resolve, reject) ->
        xhr = new XMLHttpRequest()
        xhr.open method, url
        xhr.addEventListener 'load', -> resolve(@responseText)
        xhr.addEventListener 'error', -> reject(@error.message)
        xhr.send()
    get: (url) -> ajax.request('get', url)

  views = []

  routes = []

  templates = []
  
  template = (q) ->
    return (templates[q] = ajax.get(q)) if q.match /^\//
    templates[q] = Promise.resolve $(q).innerHTML

  template(e.dataset.template) for e in $$('[data-template]')

  {
    $, $$, goto, show, hide, enable, disable, render, addClass,
    removeClass, replaceClass, listen, ignore, templates
  }

@MVStar = MVStar
