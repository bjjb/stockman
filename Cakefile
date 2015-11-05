# Where jade, stylus, coffee-script and other files live
SRC  = 'views'
# Where the HTML, CSS, JavaScript and other files appear
DIST = 'public'

# Print to the console only if the string isn't empty
log = (x) ->
  console.log(x.trim()) if x?.trim()

# Promise wrappers around Node functions
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
# Like child_process.exec, but only for files in node_modules/bin
exec = (cmd) ->
  new Promise (resolve, reject) ->
    p = require('child_process').exec "node_modules/.bin/#{cmd}"
    p.stdout.on 'data', log
    p.stderr.on 'data', log
    p.on 'exit', resolve
    p.on 'error', reject

# Returns a copy function, which takes a destination
copy = (files...) ->
  (d = 'DIST') ->
    { createReadStream, createWriteStream } = require 'fs'
    createReadStream("#{SRC}/#{f}").pipe(createWriteStream("#{d}/#{f}")) for f in files

# Render mustache data using 'src' as a template to 'dest'
mustache = (view, src, dest) ->
  new Promise (resolve, reject) ->
    { readFile, writeFile } = require 'fs'
    readFile src, 'utf8', (error, data) ->
      writeFile dest, require('mustache').render(data, view), resolve

# Replaces the index.appcache with a newly timestamped file
appcache = ->
  { name, version } = require './package'
  date = new Date().toISOString()
  mustache({ name, version, date }, "#{SRC}/index.appcache", "#{DIST}/index.appcache")

# Task functions
mkdirs = -> mkdir(DIST).then -> Promise.all(mkdir("#{DIST}/#{d}") for d in 'images css js'.split(' ')).then -> DIST
dist   = -> mkdirs().then(copy('favicon.ico', 'images/logo.svg'))
html   = -> exec "jade   -o #{DIST} -HP #{SRC}/*.jade"
css    = -> exec "stylus -u bootstrap-styl -o #{DIST}/css -m  #{SRC}/css/*.styl"
js     = -> exec "coffee -o #{DIST}/js -cm #{SRC}/js/*.coffee"
build  = -> Promise.all [dist(), appcache(), html(), css(), js()]
watch  = -> Promise.all [build(), watch.html(), watch.css(), watch.js()]
watch.html     = -> appcache().then -> exec "jade   -w -o #{DIST} -HP #{SRC}/*.jade"
watch.css      = -> appcache().then -> exec "stylus -u bootstrap-styl -w -o #{DIST} -m  #{SRC}/*.styl"
watch.js       = -> appcache().then -> exec "coffee -w -o #{DIST} -cm #{SRC}/*.coffee"
serve          = -> require('./server')(staticDirs: ['public'], port: 3000, logLevel: 'dev')
dev            = -> build().then Promise.race([watch(), serve()])
quick          = -> js().then(appcache)

# Actual tasks
task "build",  "compile the site",              build
task "quick",  "build just the JS",             quick
task "watch",  "watch for changes and compile", watch
task "serve",  "serve the site",                serve
task "dev",    "watch and serve",               dev
