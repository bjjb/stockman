# Simple API client for Google Sheets
@GoogleSheets = ({ token, XMLHttpRequest, Promise } = {}) ->
  XMLHttpRequest ?= @XMLHttpRequest
  Promise        ?= @Promise
  get = (path) ->
    ({ visibility, projection, } = {}) ->
      visibility ?= if token then 'private' else 'public'
      projection ?= 'full'
      url = "https://spreadsheets.google.com/feeds/#{path}/#{visibility}/#{projection}"
      new Promise (resolve, reject) ->
        xhr = new XMLHttpRequest()
        xhr.open('GET', url)
        xhr.setRequestHeader('Authorization', "Bearer #{token}") if token?
        xhr.addEventListener 'load', ->
          return reject(@statusText) unless @status is 200
          resolve @responseXML
        xhr.addEventListener 'error', reject
        xhr.send()
  spreadsheets:
    index: get('spreadsheets')
