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

  coffee = (req, res, next) ->
    filename = "#{app.get('views')}#{req.path.replace(/\.js$/, '.coffee')}"
    sourceMap = true
    readFile filename, 'utf8', (err, data) ->
      throw err if err?
      try
        { js, v3SourceMap, sourceMap } = coffee.compile(data, { sourceMap, filename })
      catch e
        console.error e
        return res.status(500).end()
      res.set 'Content-Type', 'text/javascript'
      res.end(js)

  appcache = (req, res, next) ->
    filename = "#{app.get('views')}#{req.path}"
    readFile filename, 'utf8', (err, data) ->
      throw err if err?
      { name, version } = require './package'
      stat '.', (err, stats) ->
        date = new Date(stats.mtime)
        appcache = mustache.render(data, { name, version, date })
        res.end(appcache)

  stylus = (req, res, next) ->
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

  app.get '/', (req, res) -> res.render 'index'
  app.use '/*.js', coffee
  app.use '/*.css', stylus
  app.use '/*.appcache', appcache
  app.get '/orders.html', (req, res) -> res.render 'orders'
  app.get '/inventory.html', (req, res) -> res.render 'inventory'
  app.get '/settings.html', (req, res) -> res.render 'settings'
  app.get '/dashboard.html', (req, res) -> res.render 'dashboard'
  app.get '/log.html', (req, res) -> res.render 'log'
  app.get '/favicon.ico', (req, res) -> res.end()

  app.listen port, ->
    { address, port } = @address()
    { name, version } = require './package'
    console.log "#{name} v#{version} listening on #{address}:#{port}"

if process.argv[1] is __filename
  server() # Start if standalone
else
  module.exports = server
