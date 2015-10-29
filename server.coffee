server = ({ port, logLevel, staticDirs, middlewares } = {}) ->
  console.log process.env.port
  port        ?= process.env.PORT or 3000
  logLevel    ?= if process.env.NODE_ENV is 'dev' then 'dev' else 'tiny'
  staticDirs  ?= [ 'public' ]
  middlewares ?= []

  express = require 'express'
  morgan  = require 'morgan'

  app = express()
  app.use morgan(logLevel)
  app.use express.static(d) for d in staticDirs
  app.use(middleware...) for middleware in middlewares

  app.listen port, ->
    { address, port } = @address()
    { name, version } = require './package'
    console.log "#{name} v#{version} listening on #{address}:#{port}"

if process.argv[1] is __filename
  server() # Start if standalone
else
  module.exports = server
