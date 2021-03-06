###*
 * It is just a Express.js wrap.
 * @extends {Express} [Ref][express]
 * [express]: http://expressjs.com/4x/api.html
###
Overview = 'service'

_ = require 'lodash'
http = require 'http'
kit = require '../kit'

###*
 * Create a Service instance.
 * @param  {Object} opts Defaults:
 * ```coffeescript
 * {
 * 	auto_log: process.env.NODE_ENV == 'development'
 * 	enable_remote_log: process.env.NODE_ENV == 'development'
 * 	enable_sse: process.env.NODE_ENV == 'development'
 * 	express: {}
 * }
 * ```
 * @return {Service}
###
service = (opts = {}) ->
	_.defaults opts, {
		auto_log: process.env.NODE_ENV == 'development'
		enable_remote_log: process.env.NODE_ENV == 'development'
		enable_sse: process.env.NODE_ENV == 'development'
		allow_origin: if process.env.NODE_ENV == 'development' then '*' else null
		express: {}
	}

	express = require 'express'
	self = express opts.express

	###*
	 * The server object of the express object.
	 * @type {http.Server} [Ref](http://nodejs.org/api/http.html#http_class_http_server)
	###
	server = http.Server self

	self.e = {}

	self._emit = (args...) ->
		if opts.auto_log
			switch args[0]
				when self.e.sse_connected
					kit.log [
						args[0].cyan
						args[1].req.path
						args[1].req.headers.referer
					].join(' | '.grey)
				else
					kit.log [args[0].cyan].concat(args[1..]).join(' | '.grey)

		self.emit.apply self, args

	_.extend self, {
		server

		express

		listen: ->
			server.listen.apply server, arguments
		close: (callback) ->
			server.close callback
	}

	jhash = new kit.jhash.constructor
	self.set 'etag', (body) ->
		hash = jhash.hash body
		len = body.length.toString(36)
		"W/\"#{len}-#{hash}\""

	if opts.allow_origin
		self.use (req, res, next) ->
			res.set 'Access-Control-Allow-Origin', opts.allow_origin
			next()

	if opts.enable_remote_log
		init_remote_log self

	if opts.enable_sse
		init_sse self

	self


init_remote_log = (self) ->
	self.post '/nobone-log', (req, res) ->
		data = ''

		req.on 'data', (chunk) ->
			data += chunk

		req.on 'end', ->
			try
				kit.log JSON.parse(data)
				res.status(200).end()
			catch e
				res.status(500).end()


init_sse = (self) ->
	###*
	 * A Server-Sent Event Manager.
	 * The namespace of nobone sse is `/nobone-sse`.
	 * For more info see [Using server-sent events][Using server-sent events].
	 * NoBone use it to implement the live-reload of web assets.
	 * [Using server-sent events]: https://developer.mozilla.org/en-US/docs/Server-sent_events/Using_server-sent_events
	 * @type {SSE}
	 * @property {Array} sessions The sessions of connected clients.
	 * @property {Integer} retry The reconnection time to use when attempting to send the event, unit is ms.
	 * Default is 1000ms.
	 * A session object is something like:
	 * ```coffeescript
	 * {
	 * 	req  # The express.js req object.
	 * 	res  # The express.js res object.
	 * }
	 * ```
	 * @example You browser code should be something like this:
	 * ```coffeescript
	 * es = new EventSource('/nobone-sse')
	 * es.addEventListener('event_name', (e) ->
	 * 	msg = JSON.parse(e.data)
	 * 	console.log(msg)
	 * ```
	###
	self.sse = {
		sessions: []
		retry: 1000
	}

	###*
	 * This event will be triggered when a sse connection started.
	 * The event name is a combination of sse_connected and req.path,
	 * for example: "sse_connected/test"
	 * @event {sse_connected}
	 * @param {SSE_session} session The session object of current connection.
	###
	self.e.sse_connected = 'sse_connected'

	###*
	 * This event will be triggered when a sse connection closed.
	 * @event {sse_close}
	 * @param {SSE_session} session The session object of current connection.
	###
	self.e.sse_close = 'sse_close'

	###*
	 * Create a sse session.
	 * @param  {Express.req} req
	 * @param  {Express.res} res
	 * @return {SSE_session}
	###
	self.sse.create = (req, res) ->
		session = { req, res }

		req.socket.setTimeout 0
		res.writeHead 200, {
			'Content-Type': 'text/event-stream'
			'Cache-Control': 'no-cache'
			'Connection': 'keep-alive'
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
			retry: #{self.sse.retry}
			data: #{msg}\n\n
			"""

		req.on 'close', ->
			_.remove self.sse.sessions, (el) -> el == session
			session.res.end()

		session.emit 'connect', 'ok'
		session

	self.use '/nobone-sse', (req, res) ->
		session = self.sse.create req, res
		self.sse.sessions.push session
		self._emit self.e.sse_connected, session

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
			else if el.req.path == path
				el.emit event, msg


module.exports = service
