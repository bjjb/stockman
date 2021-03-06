# A library to simplify OAuth2 flow.
#
# It works nicely in the (modern) browser, to authenticate web apps for Google
# API usage.
#
# ## Usage (simple)
#
# var auth = oauth2rizer(MY_CLIENT_ID, MY_CLIENT_SECRET, scopes)
# function makeAPICall(token) {
#   console.log("Authenticated successfully", token)
#   // do something with your token, like upload a file to drive
# }
# function reportError(error) {
#   console.error(error)
#   alert("Something went awry! Check the logs.")
# }
# auth().then(makeAPICall).catch(reportError)
oauth2rizer = ({ client_id, client_secret, auth_uri, token_uri, redirect_uri,
                  revoke_uri, scopes, scope, state, response_type,
                  access_type, start, refresh, exchange, redirect, remember,
                  revoke, get, post, location, oldLocation, localStorage,
                  sessionStorage, Promise, XMLHttpRequest }) ->
  state          ?= 'authorized'
  scope          ?= scopes.join(' ')
  response_type  ?= 'code'
  access_type    ?= 'offline'
  auth_uri       ?= "https://accounts.google.com/o/oauth2/auth"
  token_uri      ?= "https://www.googleapis.com/oauth2/v3/token"
  revoke_uri     = "https://accounts.google.com/o/oauth2/revoke"
  location       ?= @location
  localStorage   ?= @localStorage
  sessionStorage ?= @sessionStorage
  XMLHttpRequest ?= @XMLHttpRequest
  Promise        ?= @Promise
  redirect_uri   ?= "#{location.protocol}//#{location.host}"
  oldLocation    ?= location.toString()
  _state         = state
  buildSearch = (params) ->
    ("#{encodeURIComponent(k)}=#{encodeURIComponent(v)}" for own k, v of params).join('&')
  buildURL = (host, params) ->
    [host, buildSearch(params)].join('?')
  extractParam = (params, part) ->
    [k, v] = part.split('=')
    params[decodeURIComponent(k)] = decodeURIComponent(v)
    params
  extractParams = (search) ->
    search?.split('&').reduce(extractParam, {}) or {}
  start ?= ->
    console.debug "oauth2rizer Start"
    state = _state
    redirect(auth_uri, { client_id, response_type, redirect_uri, state, scope, access_type })
  redirect ?= (uri, params) ->
    console.debug "oauth2rizer redirect", JSON.stringify(arguments)
    oldLocation = location.toString()
    location.replace(buildURL(uri, params))
  refresh ?= (refresh_token) ->
    console.debug "oauth2rizer refresh"
    grant_type = 'refresh_token'
    post(token_uri, { client_id, client_secret, grant_type, refresh_token })
  exchange ?= (code) ->
    console.debug "oauth2rizer exchange", JSON.stringify(arguments)
    grant_type = 'authorization_code'
    post(token_uri, { code, client_id, client_secret, grant_type, redirect_uri })
  remember ?= (result) ->
    console.debug "oauth2rizer remember", JSON.stringify(arguments)
    { access_token, expires_in, token_type, refresh_token } = result
    expires_at = new Date()
    expires_at.setTime(expires_at.getTime() + expires_in * 600)
    expires_at = expires_at.getTime()
    { host } = location
    localStorage.host = host
    localStorage.refresh_token = refresh_token if refresh_token?
    sessionStorage.host = host
    sessionStorage.token_type = token_type
    sessionStorage.expires_at = expires_at
    sessionStorage.access_token = access_token
    access_token
  revoke ?= (token) ->
    console.debug "oauth2rizer revoke", JSON.stringify(arguments)
    delete localStorage.host
    delete localStorage.refresh_token
    delete sessionStorage.host
    delete sessionStorage.token_type
    delete sessionStorage.expires_at
    delete sessionStorage.access_token
    console.debug "==== REVOKE #{revoke_uri}?token=#{token}"
    location.replace("#{revoke_uri}?token=#{token}")
  get ?= (uri, params) ->
    console.debug "oauth2rizer get", JSON.stringify(arguments)
    new Promise (resolve, reject) ->
      xhr = new XMLHttpRequest
      uri = [uri, buildSearch(params)].join('?')
      xhr.open 'GET', uri
      xhr.addEventListener 'load', ->
        return reject(@statusText) unless @status is 200
        resolve(JSON.parse(@responseText))
      xhr.addEventListener 'error', reject
      xhr.send()
  post ?= (uri, params) ->
    console.debug "oauth2rizer post", JSON.stringify(arguments)
    new Promise (resolve, reject) ->
      xhr = new XMLHttpRequest
      xhr.open 'POST', uri
      xhr.setRequestHeader 'Content-Type', 'application/x-www-form-urlencoded'
      xhr.addEventListener 'load', ->
        return reject(@statusText) unless @status is 200
        resolve(JSON.parse(@responseText))
      xhr.addEventListener 'error', reject
      xhr.send(buildSearch(params))
  f = ->
    console.debug "oauth2rizer CALL", JSON.stringify(arguments)
    new Promise (resolve, reject) ->
      # 1 - we have a valid access token
      { access_token, token_type, expires_at, host } = sessionStorage
      console.debug access_token, expires_at
      return resolve(access_token) if access_token? and expires_at > new Date().getTime()
      console.debug "No access token. Refresh?"
      # 2 - we have a valid refresh token
      { refresh_token, host } = localStorage
      console.debug access_token, expires_at
      return refresh(refresh_token).then(remember).then(resolve) if refresh_token?
      console.debug "No refresh token. State?"
      # 3 - this page was redirected from an authorization request
      { state, code, error } = extractParams(location.search[1..])
      return reject(error) if error?
      return exchange(code).then(remember).then(-> redirect(redirect_uri)) if state is _state
      # 4 - None of the above,
      console.debug "No state. Start!"
      start()
  f.revoke = ->
    { access_token } = sessionStorage
    { refresh_token } = localStorage
    revoke(access_token or refresh_token)
  f.token = ->
    { access_token } = sessionStorage
  f.refresh_token = ->
    { refresh_token } = localStorage
  f

if module? and module.exports? and require?
  module.exports = oauth2rizer
else
  @oauth2rizer = oauth2rizer
