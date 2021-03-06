###*
 * An abstract renderer for any content, such as source code or image files.
 * It automatically uses high performance memory cache.
 * This renderer helps nobone to build a **passive compilation architecture**.
 * You can run the benchmark to see the what differences it makes.
 * Even for huge project the memory usage is negligible.
 * @extends {events.EventEmitter} [Ref](http://nodejs.org/api/events.html#events_class_events_eventemitter)
###
Overview = 'renderer'

_ = require 'lodash'
nobone = require '../nobone'
kit = nobone.kit
express = require 'express'
{ EventEmitter } = require 'events'
{ Promise, fs } = kit

###*
 * Create a Renderer instance.
 * @param {Object} opts Defaults:
 * ```coffeescript
 * {
 * 	enable_watcher: process.env.NODE_ENV == 'development'
 * 	auto_log: process.env.NODE_ENV == 'development'
 *
 * 	# If renderer detects this pattern, it will auto-inject `nobone_client.js`
 * 	# into the page.
 * 	inject_client_reg: /<html[^<>]*>[\s\S]*<\/html>/i
 * 	file_handlers: {
 * 		'.html': {
 * 			default: true
 * 			ext_src: ['.ejs', '.jade']
 * 			extra_watch: { path1: 'comment1', path2: 'comment2', ... } # Extra files to watch.
 * 			encoding: 'utf8' # optional, default is 'utf8'
 * 			compiler: (str, path, data) -> ...
 * 		}
 * 		'.js': {
 * 			ext_src: '.coffee'
 * 			compiler: (str, path) -> ...
 * 		}
 * 		'.css': {
 * 			ext_src: ['.styl', '.less']
 * 			compiler: (str, path) -> ...
 * 		}
 * 		'.md': {
 * 			type: 'html' # Force type, optional.
 * 			ext_src: ['.md', '.markdown']
 * 			compiler: (str, path) -> ...
 * 		}
 * 		'.jpg': {
 * 			encoding: null # To use buffer.
 * 			compiler: (buf) -> buf
 * 		}
 * 		'.png': {
 * 			encoding: null # To use buffer.
 * 			compiler: '.jpg' # Use the compiler of '.jpg'
 * 		}
 * 		'.gif' ...
 * 	}
 * }
 * ```
 * @return {Renderer}
###
renderer = (opts) -> new Renderer(opts)


class Renderer extends EventEmitter then constructor: (opts = {}) ->

	super

	_.defaults opts, {
		enable_watcher: process.env.NODE_ENV == 'development'
		auto_log: process.env.NODE_ENV == 'development'
		inject_client_reg: /<html[^<>]*>[\s\S]*<\/html>/i
		cache_limit: 1024
		file_handlers: {
			'.html': {
				default: true    # Whether it is a default handler, optional.
				ext_src: ['.ejs', '.jade']
				###*
				 * The compiler can handle any type of file.
				 * @context {File_handler} Properties:
				 * ```coffeescript
				 * {
				 * 	ext: String # The current file's extension.
				 * 	opts: Object # The current options of renderer.
				 * 	dependency_reg: RegExp # The regex to match dependency path.
				 * 	dependency_roots: Array | String # The root directories for searching dependencies.
				 *
				 * 	# The source map informantion.
				 * 	# If you need source map support, the `source_map`property
				 * 	# must be set during the compile process.
				 * 	source_map: Boolean
				 * }
				 * ```
				 * @param  {String} str Source content.
				 * @param  {String} path For debug info.
				 * @param  {Any} data The data sent from the `render` function.
				 * when you call the `render` directly. Default is an object:
				 * ```coffeescript
				 * {
				 * 	_: lodash
				 * 	inject_client: process.env.NODE_ENV == 'development'
				 * }
				 * ```
				 * @return {Promise} Promise that contains the compiled content.
				###
				compiler: (str, path, data) ->
					self = @
					switch @ext
						when '.ejs'
							@dependency_reg = /<%[\n\r\s]*include\s+([^\r\n]+)\s*%>/
							compiler = kit.require 'ejs'
						when '.jade'
							@dependency_reg = /^\s*(?:include|extends)\s+([^\r\n]+)/
							try
								compiler = kit.require 'jade'
							catch e
								kit.err '"npm install jade" first.'.red
								process.exit()
					tpl_fn = compiler.compile str, { filename: path }

					render = (data) ->
						_.defaults data, {
							_
							inject_client: process.env.NODE_ENV == 'development'
						}
						html = tpl_fn data
						if data.inject_client and
						self.opts.inject_client_reg.test html
							html += nobone.client()
						html

					if _.isObject data
						render data
					else
						func = (data = {}) ->
							render data
						func.toString = -> str
						func
			}
			'.js': {
				ext_src: '.coffee'
				compiler: (str, path, data = {}) ->
					coffee = kit.require 'coffee-script'
					code = coffee.compile str, _.defaults(data, {
						bare: true
						compress: process.env.NODE_ENV == 'production'
						compress_opts: { fromString: true }
					})
					if data.compress
						ug = kit.require 'uglify-js'
						ug.minify(code, data.compress_opts).code
					else
						code
			}
			'.css': {
				ext_src: ['.styl', '.less', '.sass', '.scss']
				compiler: (str, path, data = {}) ->
					_.defaults data, {
						filename: path
						compress: process.env.NODE_ENV == 'production'
					}
					switch @ext
						when '.styl'
							@dependency_reg = /@(?:import|require)\s+([^\r\n]+)/
							stylus = kit.require 'stylus'
							Promise.promisify(stylus.render)(str, data)

						when '.less'
							@dependency_reg = /@import\s*(?:\(\w+\))?\s*([^\r\n]+)/
							try
								less = kit.require('less')
							catch e
								kit.err '"npm install less" first.'.red
								process.exit()

							parser = new less.Parser(data)
							Promise.promisify(parser.parse)(str)
							.then (tree) ->
								Promise.resolve tree.toCSS(data)

						when '.sass', '.scss'
							@dependency_reg = /@import\s+([^\r\n]+)/
							try
								sass = kit.require 'node-sass'
							catch e
								kit.err '"npm install node-sass" first.'.red
								process.exit()
							sass.renderSync _.defaults data, {
								outputStyle: if data.compress then 'compressed' else 'nested'
								file: path
								data: str
								includePaths: [kit.path.dirname(path)]
							}
			}
			'.md': {
				type: '.html' # Force type, optional.
				ext_src: ['.md','.markdown']
				compiler: (str, path, data = {}) ->
					marked = kit.require 'marked'
					marked str, data
			}
		}
	}

	self = @

	self.opts = opts

	cache_pool = {}

	###*
	 * You can access all the file_handlers here.
	 * Manipulate them at runtime.
	 * @type {Object}
	 * @example
	 * ```coffeescript
	 * # We return js directly.
	 * renderer.file_handlers['.js'].compiler = (str) -> str
	 * ```
	###
	self.file_handlers = opts.file_handlers

	###*
	 * The cache pool of the result of `file_handlers.compiler`
	 * @type {Object} Key is the file path.
	###
	self.cache_pool = cache_pool

	# Express.js engine api.
	self.__express = (path, opts, fn) ->
		self.render path, opts
		.catch fn
		.done (str) ->
			fn null, str

	###*
	 * Set a static directory.
	 * Static folder to automatically serve coffeescript and stylus.
	 * @param  {String | Object} opts If it's a string it represents the root_dir
	 * of this static directory. Defaults:
	 * ```coffeescript
	 * {
	 * 	root_dir: '.'
	 * 	index: process.env.NODE_ENV == 'development' # Whether enable serve direcotry index.
	 * 	inject_client: process.env.NODE_ENV == 'development'
	 * }
	 * ```
	 * @return {Middleware} Experss.js middleware.
	###
	self.static = (opts = {}) ->
		if _.isString opts
			opts = { root_dir: opts }

		_.defaults opts, {
			root_dir: '.'
			index: process.env.NODE_ENV == 'development'
			inject_client: process.env.NODE_ENV == 'development'
		}

		static_handler = express.static opts.root_dir
		if opts.index
			dir_handler = kit.require('serve-index')(
				kit.fs.realpathSync opts.root_dir
				{ icons: true, view: 'details' }
			)

		return (req, res, next) ->
			req_path = decodeURIComponent(req.path)
			path = kit.path.join opts.root_dir, req_path

			rnext = -> static_handler req, res, (err) ->
				if dir_handler
					dir_handler req, res, next
				else
					next err

			handler = gen_handler path
			if handler
				handler.req_path = req_path
				get_cache(handler)
				.then (cache) ->
					get_content handler.ext_bin, cache
				.then (content) ->
					res.type handler.type or handler.ext_bin

					switch content.constructor.name
						when 'Number'
							body = content.toString()
						when 'String', 'Buffer'
							body = content
						when 'Function'
							body = content()
						else
							if cache.source_map
								if handler.is_source_map
									body = cache.source_map
								else
									source_map_comment = "sourceMappingURL=#{handler.req_path}.map"
									if handler.ext_bin == '.js'
										source_map_comment = "\n//# #{source_map_comment}\n"
									else
										source_map_comment = "\n/*# #{source_map_comment} */\n"
									body = content + source_map_comment
							else
								body = 'The compiler should produce a number, string, buffer or function: '.red +
									path.cyan + '\n' + kit.inspect(content).yellow
								err = new Error(body)
								err.name = 'unknown_type'
								throw err

					if opts.inject_client and
					res.get('Content-Type').indexOf('text/html;') == 0 and
					self.opts.inject_client_reg.test(body) and
					body.indexOf(nobone.client()) == -1
						body += nobone.client()

					res.send body
				.catch (err) ->
					switch err.name
						when self.e.compile_error
							res.status(500).end self.e.compile_error
						when 'file_not_exists'
							rnext()
						else
							throw err
				.done()
			else
				rnext()

	###*
	 * Render a file. It will auto-detect the file extension and
	 * choose the right compiler to handle the content.
	 * @param  {String | Object} path The file path. The path extension should be
	 * the same with the compiled result file. If it's an object, it can contain
	 * any number of following params.
	 * @param  {String} ext Force the extension. Optional.
	 * @param  {Object} data Extra data you want to send to the compiler. Optional.
	 * @param  {Boolean} is_cache Whether to cache the result,
	 * default is true. Optional.
	 * @param {String} req_path The http request path. Support it will make auto-reload
	 * more efficient.
	 * @return {Promise} Contains the compiled content.
	 * @example
	 * ```coffeescript
	 * # The 'a.ejs' file may not exists, it will auto-compile
	 * # the 'a.ejs' or 'a.html' to html.
	 * renderer.render('a.html').done (html) -> kit.log(html)
	 *
	 * # if the content of 'a.ejs' is '<% var a = 10 %><%= a %>'
	 * renderer.render('a.ejs', '.html').done (html) -> html == '10'
	 * renderer.render('a.ejs').done (str) -> str == '<% var a = 10 %><%= a %>'
	 * ```
	###
	self.render = (path, ext, data, is_cache = true, req_path) ->
		if _.isObject path
			{ path, ext, data, is_cache, req_path } = path

		if _.isString ext
			path = force_ext path, ext
		else if _.isBoolean ext
			is_cache = ext
			data = undefined
		else
			[data, is_cache] = [ext, data]

		is_cache ?= true

		handler = gen_handler path

		if handler
			handler.data = data
			handler.req_path = req_path
			if is_cache
				p = get_cache(handler)
			else
				p = get_src handler
			p.then (cache) ->
				get_content handler.ext_bin, cache, is_cache
		else
			throw new Error('No matched content handler for:' + path)

	###*
	 * Release the resources.
	###
	self.close = ->
		for path of cache_pool
			self.release_cache path

	###*
	 * Release memory cache of a file.
	 * @param  {String} path
	###
	self.release_cache = (path) ->
		handler = cache_pool[path]
		handler.deleted = true
		if handler.watched_list
			for wpath, watcher of handler.watched_list
				fs.unwatchFile(wpath, watcher)
		delete cache_pool[path]

	self.e = {}

	###*
	 * @event {compile_error}
	 * @param {string} path The error file.
	 * @param {Error} err The error info.
	###
	self.e.compile_error = 'compile_error'

	###*
	 * @event {watch_file}
	 * @param {string} path The path of the file.
	 * @param {fs.Stats} curr Current state.
	 * @param {fs.Stats} prev Previous state.
	###
	self.e.watch_file = 'watch_file'

	###*
	 * @event {file_deleted}
	 * @param {string} path The path of the file.
	###
	self.e.file_deleted = 'file_deleted'

	###*
	 * @event {file_modified}
	 * @param {string} path The path of the file.
	###
	self.e.file_modified = 'file_modified'

	emit = (args...) ->
		if opts.auto_log
			if args[0] == 'compile_error'
				kit.err args[1].yellow + '\n' + (args[2] + '').red
			else
				kit.log [args[0].cyan].concat(args[1..]).join(' | '.grey)

		self.emit.apply self, args

	###*
	 * Set the handler's source property.
	 * @private
	 * @param  {file_handler} handler
	 * @return {Promise} Contains handler
	###
	get_src = (handler) ->
		readfile = (path) ->
			handler.path = path
			handler.ext = kit.path.extname path

			kit.readFile path, handler.encoding
			.then (source) ->
				handler.source = source
				delete handler.content
				Promise.resolve handler

		paths = handler.ext_src.map (el) -> handler.no_ext_path + el
		check_src = ->
			path = paths.shift()
			return Promise.resolve() if not path
			kit.fileExists path
			.then (exists) ->
				if exists
					readfile path
				else
					check_src()

		check_src().then (ret) ->
			return ret if ret

			path = handler.no_ext_path + handler.ext_bin
			kit.fileExists path
			.then (exists) ->
				if exists
					readfile path
				else
					err = new Error('File not exists: ' + handler.no_ext_path)
					err.name = 'file_not_exists'
					throw err

	###*
	 * Get the compiled code
	 * @private
	 * @param  {String}  ext_bin
	 * @param  {File_handler}  cache
	 * @param  {Boolean} is_cache
	 * @return {Promise} Contains the compiled content.
	###
	get_content = (ext_bin, cache, is_cache = true) ->
		cache.last_ext_bin = ext_bin
		if ext_bin == cache.ext and not cache.force_compile
			if opts.enable_watcher and is_cache and not cache.deleted
				watch cache
			Promise.resolve cache.source
		else if cache.content
			Promise.resolve cache.content
		else
			p = try
					Promise.resolve(
						cache.compiler cache.source, cache.path, cache.data
					)
				catch err
					Promise.reject err

			p.then (content) ->
				cache.content = content
				delete cache.error
			.catch (err) ->
				if _.isString err
					err = new Error(err)
				emit self.e.compile_error, cache.path, err.stack
				err.name = self.e.compile_error
				cache.error = err
			.then ->
				if opts.enable_watcher and is_cache and not cache.deleted
					watch cache

				if cache.error
					throw cache.error
				else
					Promise.resolve cache.content

	###*
	 * Set handler cache.
	 * @param  {File_handler} handler
	 * @return {Promise}
	###
	get_cache = (handler) ->
		handler.compiler ?= (bin) -> bin

		cache = _.find cache_pool, (v, k) ->
			for ext in handler.ext_src.concat(handler.ext_bin)
				if handler.no_ext_path + ext == k
					return true
			return false

		if cache == undefined
			get_src(handler).then (cache) ->
				cache_pool[cache.path] = cache
				if _.keys(cache_pool).length > opts.cache_limit
					min_handler = _(cache_pool).values().min('ctime').value()
					if min_handler
						self.release_cache min_handler.path
				Promise.resolve cache
		else
			if cache.error
				throw cache.error
			else
				Promise.resolve cache

	###*
	 * Generate a file handler.
	 * @param  {String} path
	 * @return {File_handler}
	###
	gen_handler = (path) ->
		# TODO: This part is somehow too complex.

		ext_bin = kit.path.extname path

		if ext_bin == '.map'
			path = remove_ext path
			ext_bin = kit.path.extname path
			is_source_map = true

		if ext_bin == ''
			handler = _.find self.file_handlers, (el) -> el.default
		else if self.file_handlers[ext_bin]
			handler = self.file_handlers[ext_bin]
			if self.file_handlers[ext_bin].ext_src and
			ext_bin in self.file_handlers[ext_bin].ext_src
				handler.force_compile = true
		else
			handler = _.find self.file_handlers, (el) ->
				el.ext_src and ext_bin in el.ext_src

		if handler
			handler = _.cloneDeep(handler)
			handler.ctime = Date.now()
			handler.is_source_map = is_source_map
			handler.watched_list = {}
			handler.ext_src ?= ext_bin
			handler.ext_src = [handler.ext_src] if _.isString(handler.ext_src)
			handler.ext_bin = ext_bin
			handler.encoding = if handler.encoding == undefined then 'utf8' else handler.encoding
			handler.dirname = kit.path.dirname(path)
			handler.no_ext_path = remove_ext path
			if _.isString handler.compiler
				handler.compiler = self.file_handlers[handler.compiler].compiler

			handler.opts = self.opts

		handler

	watch = (handler) ->
		# async lock, make sure one file won't be watched twice.
		watch.processing ?= []

		watcher = (path, curr, prev, is_deletion) ->
			# If moved or deleted
			if is_deletion
				self.release_cache path
				emit self.e.file_deleted, path + ' -> '.cyan + handler.path

			else if curr.mtime != prev.mtime
				get_src(handler)
				.then ->
					get_content handler.last_ext_bin, handler
				.catch(->)
				.then ->
					emit(
						self.e.file_modified
						path
						handler.type or handler.ext_bin
						handler.req_path
					)

		gen_watch_list(handler)
		.then ->
			return if _.keys(handler.new_watch_list).length == 0

			for path of handler.new_watch_list
				continue if _.isFunction(handler.watched_list[path])
				handler.watched_list[path] = kit.watch_file path, watcher
				emit self.e.watch_file, path, handler.req_path

			delete handler.new_watch_list

			# Unlock the src file.
			_.remove watch.processing, (el) -> el == handler.path
		.done()

	# Parse the dependencies.
	get_dependencies = (handler, curr_paths) ->
		###
			Trim cases:
				"name"\s\s
				"name";\s\s
		###
		trim = (path) ->
			path
			.replace /^[\s'"]+/, ''
			.replace /[\s'";]+$/, ''

		gen_dep_paths = (matches) ->
			Promise.all matches.map (m) ->
				path = trim m.match(handler.dependency_reg)[1]
				unless kit.path.extname(path)
					path = path + handler.ext

				dep_paths = handler.dependency_roots.map (root) ->
					kit.path.join root, path

				get_dependencies handler, dep_paths

		reg = new RegExp(handler.dependency_reg.source, 'g')
		if curr_paths
			kit.glob curr_paths
			.then (paths) ->
				Promise.all paths.map (path) ->
					kit.readFile(path, 'utf8')
					.then (str) ->
						# The point to add path to watch list.
						handler.new_watch_list[path] = null

						matches = str.match reg
						return Promise.resolve() if not matches
						gen_dep_paths matches
			.catch -> return
		else
			return Promise.resolve() if not handler.source
			matches = handler.source.match reg
			return Promise.resolve() if not matches
			gen_dep_paths matches

	gen_watch_list = (handler) ->
		if watch.processing.indexOf(handler.path) > -1
			return Promise.resolve()

		# lock current src file.
		watch.processing.push handler.path

		# Add the src file to watch list.
		if not _.isFunction(handler.watched_list[handler.path])
			handler.watched_list[handler.path] = null

		# Make sure the dependency_roots is string.
		handler.dependency_roots ?= []
		if _.isString handler.dependency_roots
			handler.dependency_roots = [handler.dependency_roots]
		handler.dependency_roots.push handler.dirname

		handler.new_watch_list = {}
		_.extend handler.new_watch_list, handler.extra_watch
		handler.new_watch_list[handler.path] = handler.watched_list[handler.path]

		if handler.dependency_reg
			get_dependencies handler
		else
			Promise.resolve()

	force_ext = (path, ext) ->
		remove_ext(path) + ext

	remove_ext = (path) ->
		path.replace /\.\w+$/, ''

module.exports = renderer
