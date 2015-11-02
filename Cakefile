SRC  = '.'
DIST = 'public'

log = (x) ->
  console.log(x.trim()) if x?.trim()
ls = (d) ->
  new Promise (resolve, reject) ->
    require('fs').readdir d, (error, entries) ->
      return reject(error) if error?
      resolve(require('path').join(d, e) for e in entries when e not in ['.', '..'])
unlink = (f) ->
  new Promise (resolve, reject) ->
    require('fs').unlink f, (error) ->
      return reject(error) if error
      resolve()
rmdir = (d) ->
  new Promise (resolve, rejext) ->
    require('fs').rmdir d, (error) ->
      return reject(error) if error
      resolve()
rm = (f) ->
  new Promise (resolve, reject) ->
    require('fs').stat f,  (stats) ->
      return unlink(f).then(resolve) if stats.isFile()
      ls(f).then((entries) -> Promise.all(rm(e) for e in entries)).then -> rmdir(f).then(resolve)
mkdir = (d) ->
  new Promise (resolve, reject) ->
    require('fs').mkdir d, (err) ->
      return reject(err) if err? and err.code isnt 'EEXIST'
      resolve(d)
exec = (cmd) ->
  new Promise (resolve, reject) ->
    p = require('child_process').exec "node_modules/.bin/#{cmd}"
    p.stdout.on 'data', log
    p.stderr.on 'data', log
    p.on 'exit', resolve
    p.on 'error', reject
copy = (files...) ->
  (d = 'DIST') ->
    { createReadStream, createWriteStream } = require 'fs'
    createReadStream("#{SRC}/#{f}").pipe(createWriteStream("#{d}/#{f}")) for f in files
mustache = (view, src, dest) ->
  new Promise (resolve, reject) ->
    { readFile, writeFile } = require 'fs'
    readFile src, 'utf8', (error, data) ->
      writeFile dest, require('mustache').render(data, view), resolve
dist   = -> mkdir(DIST).then(copy('favicon.ico', 'logo.svg'))
html   = -> exec "jade   -o #{DIST} -HP #{SRC}/*.jade"
css    = -> exec "stylus -u bootstrap-styl -o #{DIST} -m  #{SRC}/*.styl"
js     = -> exec "coffee -o #{DIST} -cm #{SRC}/*.coffee"
appcache = ->
  { name, version } = require './package'
  date = new Date().toISOString()
  mustache({ name, version, date }, "#{SRC}/index.appcache", "#{DIST}/index.appcache")
build  = -> Promise.all [dist(), appcache(), html(), css(), js()]
watch  = -> Promise.all [build(), watch.html(), watch.css(), watch.js()]
watch.html     = -> appcache().then -> exec "jade   -w -o #{DIST} -HP #{SRC}/*.jade"
watch.css      = -> appcache().then -> exec "stylus -u bootstrap-styl -w -o #{DIST} -m  #{SRC}/*.styl"
watch.js       = -> appcache().then -> exec "coffee -w -o #{DIST} -cm #{SRC}/*.coffee"
server  = -> build().then Promise.race([watch(), serve()])
serve = -> require('./server')(staticDirs: ['public'], port: 3000, logLevel: 'dev')

task "build",  "compile the site",              build
task "watch",  "watch for changes and compile", watch
task "server", "serve the site",                server
