# Simple API client for Google Sheets
#
# 
# token:          an OAuth2 Bearer token. See https://goo.gl/hvrAd3
# XMLHttpRequest: use this to override the HTTP library with something
#                 compatible, like [xhr2](http://npmjs.com/package/xhr2)
# Promise:        use this to override the Promise library with something
#                 compatible, like [q.Promise](http://npmjs.com/package/q)
# rewrite:        a function to rewrite the URL - for example, the proxy that
#                 you should use with the GoogleSheets middleware should be
#                    function(url) {
#                      // assuming the middleware is mounted at /google-sheets
#                      return "/google-sheets/" + url
#                    }
# respond:        a function to determine what gets resolved - it's called
#                 from within the context of the XMLHTTPRequest's onload
#                 handler, and the default is to return the responseXML. It
#                 takes the load event as an argument.
GoogleSheets = ({ token, XMLHttpRequest, Promise, rewrite, respond } = {}) ->
  XMLHttpRequest ?= @XMLHttpRequest
  Promise        ?= @Promise
  rewrite        ?= (url) -> url
  respond        ?= (e) -> e.target.responseXML
  index = ({ visibility, projection } = {}) ->
    visibility ?= if token then 'private' else 'public'
    projection ?= 'full'
    url = "https://spreadsheets.google.com/feeds/spreadsheets/#{visibility}/#{projection}"
    get(url)
  get = (url, headers) ->
    headers ?= if token? then { Authorization: "Bearer #{token}"} else {}
    new Promise (resolve, reject) ->
      xhr = new XMLHttpRequest()
      xhr.open('GET', rewrite(url))
      xhr.setRequestHeader(k, v) for own k, v of headers
      xhr.withCredentials = !!token
      xhr.addEventListener 'load', (e) ->
        return reject(@responseText) unless @status is 200
        resolve respond(e)
      xhr.addEventListener 'error', reject
      xhr.send()
  { index, get }

if module? and module.exports? and require?
  # A dead simple proxy. Grabs the authorization code from the header, and
  # makes the request to Google Sheets, responding with the result.
  GoogleSheets.proxy = ->
    XMLHttpRequest = require 'xhr2'
    Promise        = require 'bluebird'
    express        = require 'express'

    respond = (e) -> e.target
    googleSheets = GoogleSheets({ XMLHttpRequest, Promise, respond })

    app = express.Router()
    app.get /\/(.+)/, (req, res) ->
      url = req.params[0]
      console.log "GoogleSheets.proxy #{req.method} #{url}"
      googleSheets.get(url, req.headers).then (xhr) ->
        res.set('content-type', xhr.getResponseHeader('Content-Type'))
        res.send(xhr.responseText)
    app
    
  module.exports = GoogleSheets
else
  @GoogleSheets = GoogleSheets
