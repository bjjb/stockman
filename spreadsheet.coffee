log = (level) -> (x) -> (console[level](x); x)

get = (sheets) -> (id) -> sheets.get(id)

render = (q) ->
  (view) ->
    element = @document.querySelector(q)
    { templ } = element.dataset
    if templ?
      template = @document.querySelector(templ)?.innerHTML
      if template?
        element.innerHTML = Mustache.render(template, view)
      else
        console.warn("Template not found:", template)
    else
      console.warn("Element has no data-template, skipping:", e)
    element

# Attempts to load the spreadsheet 'id'.
loadSpreadsheet = (sheets) ->
  (id) ->
    Promise.reject("Not implemented")

# Creates a new spreadsheet, on the user's Google Drive. The ID is saved to
# @localStorage.
createSpreadsheet = (sheets) ->
  (err) ->
    console.warn(err)
    Promise.reject("Not implemented")

# Make the user choose a spreadsheet. Gets the list of available spreadsheets
# and displays them in #choose-ss. When they pick one from the <select>, it
# checks that it has the appropriate worksheets. If so, it enables the
# submit button, and remembers the sheet's id in localStorage. It eventually
# resolves to the sheet's ID.
chooseSpreadsheet = (sheets) ->
  ->
    new Promise (resolve, reject) ->
      sheets.index().then (doc) ->
        spreadsheets = ({
          id: e.querySelector('id').innerHTML
          title: e.querySelector('title').innerHTML
        } for e in doc.querySelectorAll('entry'))
        changed = -> # <select>
          @form.querySelector('.spinner').hidden = false
          @form.querySelector('button').disabled = true
          check = (id) =>
            sheets.get(id).then (doc) =>
              console.debug(doc)
              link = doc.querySelector('link[rel="http://schemas.google.com/spreadsheets/2006#worksheetsfeed"]')
              console.debug("LINK: ", link)
              href = link.getAttribute('href')
              href = "http://xorigin.herokuapp.com/#{href}"
              console.debug(href)
              sheets.get(href).then (doc) =>
                console.log("WORKSHEETS...", doc)
                @form.querySelector('.spinner').hidden = true
                reject "OK"
              .catch -> console.error(arguments)
          valid = =>
            group = @form.querySelector('.form-group')
            group.classList.remove('has-warning')
            group.classList.remove('has-error')
            group.classList.add('has-success')
            @form.querySelector('.help-block').innerHTML = ''
            @form.querySelector('button').disabled = false
          invalid = (message) =>
            group = @form.querySelector('.form-group')
            group.classList.remove('has-warning')
            group.classList.remove('has-success')
            group.classList.add('has-error')
            @form.querySelector('.help-block').innerHTML = message
          check(@value).then(valid).catch(invalid)
        select = render('#choose-ss select')({spreadsheets})
        done = ->
          @removeEventListener 'submit', done
          resolve select.value
        select.addEventListener 'change', changed
        location.hash = '#choose-ss'

Spreadsheet = (config) ->
  oauth2rizer(config)().then (token) ->
    sheets = GoogleSheets({ token })
    load   = loadSpreadsheet(sheets)
    choose = chooseSpreadsheet(sheets)
    create = createSpreadsheet(sheets)
    { spreadsheet } = localStorage
    return sheets.get(spreadsheet).then(load) if spreadsheet?
    load(spreadsheet).catch(choose).catch(create)

@stockman ?= {}
@stockman.Spreadsheet = Spreadsheet
