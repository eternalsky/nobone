###*
 * It is just a Express.js wrap.
 * @extends {Express}
###
Overview = 'service'

_ = require 'lodash'
http = require 'http'
kit = require '../kit'
emit = null

###*
 * Create a Service instance.
 * @param  {Object} opts Defaults:
 * ```coffee
 * {
 * 	auto_log: process.env.NODE_ENV == 'development'
 * 	enable_remote_log: process.env.NODE_ENV == 'development'
 * 	enable_sse: process.env.NODE_ENV == 'development'
 * 	express: {}
 * }```
 * @return {Service}
###
service = (opts = {}) ->
	_.defaults opts, service.defaults

	express = require 'express'
	self = express opts.express

	server = http.Server self

	self.e = {}

	emit = ->
		if opts.auto_log
			kit.log arguments[0].cyan

		self.emit.apply self, arguments

	###*
	 * Triggered when a sse connection started.
	 * The event name is a combination of sse_connected and req.path,
	 * for example: "sse_connected/test"
	 * @event sse_connected
	 * @param {SSE_session} The session object of current connection.
	###
	self.e.sse_connected = 'sse_connected'

	###*
	 * When a sse connection closed.
	 * @event sse_close
	 * @type {SSE_session} The session object of current connection.
	###
	self.e.sse_close = 'sse_close'

	_.extend self, {
		server

		listen: ->
			server.listen.apply server, arguments
		close: (callback) ->
			server.close callback
	}

	jhash = new kit.jhash.constructor
	self.set 'etag', (body) ->
		kit.log body.constructor.name.red
		hash = jhash.hash body
		len = body.length.toString(36)
		"W/\"#{len}-#{hash}\""

	if opts.enable_remote_log
		init_remote_log self

	if opts.enable_sse
		init_sse self

	self

service.defaults = {
	auto_log: process.env.NODE_ENV == 'development'
	enable_remote_log: process.env.NODE_ENV == 'development'
	enable_sse: process.env.NODE_ENV == 'development'
	express: {}
}


init_remote_log = (self) ->
	self.post '/nobone-log', (req, res) ->
		data = ''

		req.on 'data', (chunk) ->
			data += chunk

		req.on 'end', ->
			try
				kit.log JSON.parse(data)
				res.send 200
			catch e
				res.send 500


init_sse = (self) ->
	###*
	 * A Server-Sent Event Manager.
	 * The namespace of nobone sse is '/nobone-sse',
	 * @example You browser code should be something like this:
	 * ```coffee
	 * es = new EventSource('/nobone-sse')
	 * es.addEventListener('event_name', (e) ->
	 * 	msg = JSON.parse(e.data)
	 * 	console.log(msg)
	 * ```
	 * @type {SSE}
	###
	self.sse = {
		sessions: []
	}

	create_session = (req, res) ->
		session = {
			path: req.path
			req
			res
		}

		###*
		 * Emit message to client.
		 * @param  {String} event The event name.
		 * @param  {Object | String} msg The message to send to the client.
		###
		session.emit = (event, msg = '') ->
			msg = JSON.stringify msg
			res.write """
			id: #{Date.now()}
			event: #{event}
			data: #{msg}\n\n
			"""

		session

	self.use '/nobone-sse', (req, res) ->
		req.socket.setTimeout 0
		req.on 'close', ->
			s = _.remove self.sse.sessions, (el) -> el.res == res
			emit self.e.sse_close + req.path, s[0]

		res.writeHead 200, {
			'Content-Type': 'text/event-stream'
			'Cache-Control': 'no-cache'
			'Connection': 'keep-alive'
		}

		session = create_session req, res
		self.sse.sessions.push session

		emit self.e.sse_connected + req.path, session
		self.sse.emit 'connect', 'ok'

	###*
	 * Broadcast a event to clients.
	 * @param {String} event The event name.
	 * @param {Object | String} msg The data you want to emit to session.
	 * @param {String} [path] The namespace of target sessions. If not set,
	 * broadcast to all clients.
	###
	self.sse.emit = (event, msg, path = '') ->
		for el in self.sse.sessions
			if not path
				el.emit event, msg
			else if el.path == path
				el.emit event, msg


module.exports = service
