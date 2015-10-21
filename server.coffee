server = ({ port, logLevel, staticDirs, middlewares } = {}) ->
  port        ?= process.env.PORT or 3474
  logLevel    ?= if process.env.NODE_ENV is 'dev' then 'dev' else 'tiny'
  staticDirs  ?= [ 'public' ]
  middlewares ?= [
    [ '/oauth', require('./oauth2rizer').middleware ]
    [ '/google-sheets', require('./google-sheets').middleware ]
  ]

  express = require 'express'
  morgan  = require 'morgan'
  sheets  = require './google-sheets'

  app = express()
  app.use morgan(logLevel)
  app.use express.static(d) for d in staticDirs

  console.log("app.use: ", middleware...) for middleware in middlewares
  app.use(middleware...) for middleware in middlewares

  app.listen port or process.env.PORT or 3000, ->
    { address, port } = @address()
    { name, version } = require './package'
    console.log "#{name} v#{version} listening on #{address}:#{port}"

if process.argv[1] is __filename
  server()
else # Start if standalone
  module.exports = server
