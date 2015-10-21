express = require 'express'
morgan  = require 'morgan'
sheets  = require './google-sheets'

app = express()
app.use morgan('tiny')
app.use express.static('.')

app.use '/google-sheets*', sheets.GoogleSheets.proxy
#app.use oauth2.oauth2rizer.proxy

app.start = (port) -> app.listen port or process.env.PORT or 3000, ->
  { address, port } = @address()
  { name, version } = require './package'
  console.log "#{name} v#{version} listening on #{address}:#{port}"

app.start() if process.argv[1] is __filename
module.exports = app.start.bind(app)
