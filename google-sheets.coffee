# Simple API client for Google Sheets
GoogleSheets = ({ token, XMLHttpRequest, Promise, CORSProxy } = {}) ->
  XMLHttpRequest ?= @XMLHttpRequest
  Promise        ?= @Promise
  class Document
    constructor: (@document) ->
      @entries = (new Document(e) for e in @document.querySelectorAll('entry'))
      @links = @document.querySelectorAll('link')
      @author =
        name: @document.querySelector('author name').innerHTML
        email: @document.querySelector('author email').innerHTML
      @id = @document.querySelector('id').innerHTML
      @title = @document.querySelector('title').innerHTML
      @content = @document.querySelector('content').innerHTML
      @updated = new Date(@document.querySelector('updated').innerHTML)
      @worksheetsFeed = (link.getAttribute('href') for link in @links when link.rel?.match /#worksheetsfeed$/)[0]
    @worksheets: -> get(worksheetsFeed)

  index = ({ visibility, projection } = {}) ->
    visibility ?= if token then 'private' else 'public'
    projection ?= 'full'
    url = "https://spreadsheets.google.com/feeds/spreadsheets/#{visibility}/#{projection}"
    get(url)
  get = (url, headers) ->
    headers ?= if token? then { Authorization: "Bearer #{token}"} else {}
    url = "#{CORSProxy}/#{url}" if CORSProxy?
    console.debug("GET #{url}")
    new Promise (resolve, reject) ->
      xhr = new XMLHttpRequest()
      xhr.open('GET', url)
      xhr.setRequestHeader(k, v) for own k, v of headers
      xhr.addEventListener 'load', ->
        return reject(@statusText) unless @status is 200
        resolve @responseXML
      xhr.addEventListener 'error', reject
      xhr.send()
  { index, get }

middleware = (req, res, next) ->
  res.end("Google Sheets proxy not implented.")

@GoogleSheets = GoogleSheets
module.exports.middleware = middleware if module?.exports?
