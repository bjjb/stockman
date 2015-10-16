task "build", "compile the site", ->
  { exec } = require 'child_process'
  log = (error, stdout, stderr) ->
    console.log stdout if stdout?
    console.error stderr if stderr?
  exec "./node_modules/.bin/jade   -o public -P  *.jade", log
  exec "./node_modules/.bin/stylus -o public -m  *.styl", log
  exec "./node_modules/.bin/coffee -o public -cm *.coffee", log

task "serve", "serve the compiled site", ->
  invoke "build"
  express = require 'express'
  app = express()
  app.use express.static('public')
  app.listen process.env.PORT or 3000, ->
    { address, port } = @address()
    console.log "Listening on #{address}:#{port}"
