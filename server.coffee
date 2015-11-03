{ stat, readFile } = require 'fs'
{ extname } = require 'path'
coffee = require 'coffee-script'
stylus = require 'stylus'
bootstrap = require 'bootstrap-styl'
mustache = require 'mustache'

server = ({ port, logLevel, staticDirs, middlewares } = {}) ->
  port        ?= process.env.PORT or 3000
  logLevel    ?= if process.env.NODE_ENV is 'dev' then 'dev' else 'tiny'
  staticDirs  ?= [ 'public' ]
  middlewares ?= []

  express = require 'express'
  morgan  = require 'morgan'

  app = express()

  app.use morgan(logLevel)
  app.use express.static(d) for d in staticDirs

  app.set 'view engine', 'jade'

  app.use (req, res, next) ->
    return next() unless extname(req.path) is '.js'
    filename = "#{app.get('views')}#{req.path.replace(/\.js$/, '.coffee')}"
    sourceMap = true
    readFile filename, 'utf8', (err, data) ->
      throw err if err?
      { js, v3SourceMap, sourceMap } = coffee.compile(data, { sourceMap, filename })
      res.set 'Content-Type', 'text/javascript'
      res.end(js)
      console.log "Rendered #{filename}"

  app.use (req, res, next) ->
    return next() unless req.path is '/index.appcache'
    filename = "#{app.get('views')}#{req.path}"
    readFile filename, 'utf8', (err, data) ->
      throw err if err?
      { name, version } = require './package'
      stat 'views', (err, stats) ->
        throw err if err
        date = stats.mtime
        appcache = mustache.render(data, { name, version, date })
        res.end(appcache)
        console.log "Rendered #{filename} (#{date})"

  app.use (req, res, next) ->
    return next() unless extname(req.path) is '.css'
    filename = "#{app.get('views')}#{req.path.replace(/\.css$/, '.styl')}"
    readFile filename, 'utf8', (err, data) ->
      throw err if err?
      stylus(data)
        .set 'filename', filename
        .set 'sourcemap', { basepath: 'views', inline: true }
        .use bootstrap()
        .render (err, css) ->
          throw err if err?
          res.set 'Content-Type', 'text/css'
          res.end(css)
          console.log "Rendered #{filename}"

  app.use(middleware...) for middleware in middlewares

  app.get '/', (req, res) -> res.render 'index'
  app.get '/orders', (req, res) -> res.render 'orders'
  app.get '/inventory', (req, res) -> res.render 'inventory'
  app.get '/settings', (req, res) -> res.render 'settings'
  app.get '/images/logo.svg', (req, res) -> readFile 'views/images/logo.svg', (err, data) -> res.end(data)
  app.get '/favicon.ico', (req, res) -> res.end()

  app.listen port, ->
    { address, port } = @address()
    { name, version } = require './package'
    console.log "#{name} v#{version} listening on #{address}:#{port}"

if process.argv[1] is __filename
  server() # Start if standalone
else
  module.exports = server
