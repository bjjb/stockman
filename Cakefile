SRC  = '.'
DIST = 'public'

log = (x) ->
  console.log(x) if x?.trim()
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
dist   = -> mkdir(DIST)
html   = -> exec "jade   -o #{DIST} -HP #{SRC}/*.jade"
css    = -> exec "stylus -o #{DIST} -m  #{SRC}/*.styl"
js     = -> exec "coffee -o #{DIST} -cm #{SRC}/*.coffee"
build  = -> Promise.all [dist(), html(), css(), js()]
watch  = -> Promise.all [build(), watch.html(), watch.css(), watch.js()]
watch.html   = -> exec "jade   -w -o #{DIST} -HP #{SRC}/*.jade"
watch.css    = -> exec "stylus -w -o #{DIST} -m  #{SRC}/*.styl"
watch.js     = -> exec "coffee -w -o #{DIST} -cm #{SRC}/*.coffee"
server  = -> build().then Promise.race([watch(), serve()])
serve = -> require('./server')(staticDirs: ['public'], port: 3474, logLevel: 'dev')

task "build",  "compile the site",              build
task "watch",  "watch for changes and compile", watch
task "server", "serve the site",                server
