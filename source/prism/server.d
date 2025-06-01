module prism.server;

import std;
import prism.ws;
import core.thread;
import core.sync.mutex;
import core.sync.condition;

/** 
 * Response type enumeration.
 */
enum ResponseType
{
	HTML,
	JSON,
	PLAINTEXT,
	BLOB,
	REDIRECT
}

/** 
 * Response structure containing content and type.
 */
struct Response
{
	ubyte[] content;
	ResponseType type;
	string[string] headers;
	int statusCode = 200;

	this(ubyte[] content, ResponseType type = ResponseType.HTML, int statusCode = 200)
	{
		this.content = content;
		this.type = type;
		this.statusCode = statusCode;
	}

	this(string content, ResponseType type = ResponseType.HTML, int statusCode = 200)
	{
		this(cast(ubyte[]) content, type, statusCode);
	}
}

/** 
 * Request context containing path parameters and query parameters.
 */
struct RequestContext
{
	string[string] params;
	string[string] query;
	string body;
	string path;
	string method;
}

/** 
 * Route handlers that can return different response types.
 */
alias RouteHandler = Response delegate(RequestContext context);
alias PostRouteHandler = Response delegate(RequestContext context);
alias PutRouteHandler = Response delegate(RequestContext context);
alias PatchRouteHandler = Response delegate(RequestContext context);
alias DeleteRouteHandler = Response delegate(RequestContext context);
alias WebSocketConnectHandler = void delegate(WebSocketConnection conn);
alias WebSocketMessageHandler = void delegate(WebSocketConnection conn, string message);
alias WebSocketBinaryHandler = void delegate(WebSocketConnection conn, ubyte[] data);
alias WebSocketCloseHandler = void delegate(WebSocketConnection conn);

/**
 * WebSocket route structure.
 */
struct WebSocketRoute
{
	string pattern;
	string[] paramNames;
	WebSocketConnectHandler onConnect;
	WebSocketMessageHandler onMessage;
	WebSocketBinaryHandler onBinary;
	WebSocketCloseHandler onClose;
}

/** 
 * Route pattern structure to handle parameterized routes.
 */
struct RoutePattern
{
	string pattern;
	string[] paramNames;
	Regex!char compiledRegex;
	RouteHandler handler;
	PostRouteHandler postHandler;
	PutRouteHandler putHandler;
	PatchRouteHandler patchHandler;
	DeleteRouteHandler deleteHandler;
	string method;
}

/** 
 * Static file mount configuration.
 */
struct StaticMount
{
	string mountPath;
	string rootPath;
	bool listDirectories = false;
}

/**
 * Thread pool for handling connections.
 */
class ThreadPool
{
	private Thread[] workers;
	private Socket[] taskQueue;
	private Mutex queueMutex;
	private void delegate(Socket) taskHandler;
	private Condition queueCondition;
	private shared bool running = true;

	this(size_t numThreads, void delegate(Socket) handler)
	{
		queueMutex = new Mutex();
		queueCondition = new Condition(queueMutex);
		taskHandler = handler;

		for (size_t i = 0; i < numThreads; i++)
		{
			workers ~= new Thread(&workerLoop);
			workers[$ - 1].start();
		}
	}

	void addTask(Socket client)
	{
		synchronized (queueMutex)
		{
			taskQueue ~= client;
			queueCondition.notify();
		}
	}

	private void workerLoop()
	{
		while (running)
		{
			Socket client = null;

			synchronized (queueMutex)
			{
				while (taskQueue.length == 0 && running)
					queueCondition.wait();

				if (taskQueue.length > 0)
				{
					client = taskQueue[0];
					taskQueue = taskQueue[1 .. $];
				}
			}

			if (client !is null)
			{
				try
				{
					taskHandler(client);
				}
				catch (Exception e)
				{
				}
			}
		}
	}
}

/** 
 * The application itself.
 */
class PrismApplication
{
	private TcpSocket server;
	private RoutePattern[] routes;
	private WebSocketRoute[] wsRoutes;
	private StaticMount[] staticMounts;
	private string[string] mimeTypeCache;
	private ThreadPool threadPool;
	private shared bool running = true;

	/** 
	* Instantiate a new application.
	*
	* Params:
	*   port = Port to operate on
	*   numThreads = Number of worker threads (default: 8)
	*/
	this(ushort port = 8080, size_t numThreads = 8)
	{
		server = new TcpSocket();

		server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		server.setOption(SocketOptionLevel.SOCKET, SocketOption.TCP_NODELAY, true);
		server.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVBUF, 262_144);
		server.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDBUF, 262_144);
		server.bind(new InternetAddress(port));
		server.listen(2048);

		populateMimeTypeCache();
		threadPool = new ThreadPool(numThreads, &handleClient);
	}

	/**
	 * Register WebSocket route.
	 */
	void websocket(string path,
		WebSocketConnectHandler onConnect = null,
		WebSocketMessageHandler onMessage = null,
		WebSocketBinaryHandler onBinary = null,
		WebSocketCloseHandler onClose = null)
	{
		auto pattern = parseRoutePattern(path);
		wsRoutes ~= WebSocketRoute(
			pattern.pattern,
			pattern.paramNames,
			onConnect,
			onMessage,
			onBinary,
			onClose
		);
	}

	/** 
	 * Populate the MIME type cache.
	 */
	private void populateMimeTypeCache()
	{
		mimeTypeCache[".html"] = "text/html";
		mimeTypeCache[".htm"] = "text/html";
		mimeTypeCache[".css"] = "text/css";
		mimeTypeCache[".js"] = "application/javascript";
		mimeTypeCache[".json"] = "application/json";
		mimeTypeCache[".png"] = "image/png";
		mimeTypeCache[".jpg"] = "image/jpeg";
		mimeTypeCache[".jpeg"] = "image/jpeg";
		mimeTypeCache[".gif"] = "image/gif";
		mimeTypeCache[".svg"] = "image/svg+xml";
		mimeTypeCache[".ico"] = "image/x-icon";
		mimeTypeCache[".pdf"] = "application/pdf";
		mimeTypeCache[".txt"] = "text/plain";
		mimeTypeCache[".xml"] = "application/xml";
	}

	/**
	 * Handle WebSocket upgrade.
	 */
	private bool handleWebSocketUpgrade(Socket client, string request, string path)
	{
		if (!request.toLower().canFind("upgrade: websocket"))
			return false;

		WebSocketRoute* matchedRoute = null;
		RequestContext context;

		foreach (ref route; wsRoutes)
		{
			auto routeRegex = regex(route.pattern);
			auto match = matchFirst(path, routeRegex);

			if (match)
			{
				matchedRoute = &route;
				for (size_t i = 0; i < route.paramNames.length && i + 1 < match.length;
					i++)
				{
					context.params[route.paramNames[i]] = match[i + 1];
				}
				break;
			}
		}

		if (!matchedRoute)
			return false;

		auto keyMatch = request.matchFirst(regex(r"Sec-WebSocket-Key:\s*([^\r\n]+)"));
		if (!keyMatch)
			return false;

		string wsKey = keyMatch[1].strip();
		string acceptKey = generateWebSocketAcceptKey(wsKey);
		string response = "HTTP/1.1 101 Switching Protocols\r\n" ~
			"Upgrade: websocket\r\n" ~
			"Connection: Upgrade\r\n" ~
			"Sec-WebSocket-Accept: " ~ acceptKey ~ "\r\n\r\n";

		client.send(cast(ubyte[]) response);

		auto wsConn = new WebSocketConnection(client);
		auto wsThread = new Thread({
			handleWebSocketConnection(wsConn, *matchedRoute, context);
		});

		wsThread.start();

		return true;
	}

	/**
	 * Generate WebSocket accept key.
	 */
	private string generateWebSocketAcceptKey(string key)
	{
		import std.digest.sha : sha1Of;

		return Base64.encode(sha1Of(key ~ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")).idup;
	}

	/**
	 * Handle WebSocket connection lifecycle.
	 */
	private void handleWebSocketConnection(WebSocketConnection conn, WebSocketRoute route, RequestContext context)
	{
		if (route.onConnect)
			route.onConnect(conn);

		try
		{
			while (conn.isConnectionOpen())
			{
				auto frame = conn.receiveFrame();

				switch (frame.opcode)
				{
				case WebSocketOpcode.TEXT:
					if (route.onMessage)
						route.onMessage(conn, cast(string) frame.payload);
					break;

				case WebSocketOpcode.BINARY:
					if (route.onBinary)
						route.onBinary(conn, frame.payload);
					break;

				case WebSocketOpcode.PING:
					conn.pong(frame.payload);
					break;

				case WebSocketOpcode.PONG:
					break;

				case WebSocketOpcode.CLOSE:
					conn.close();
					break;

				default:
					break;
				}
			}
		}
		catch (Exception e)
		{
			writeln("WebSocket error: ", e.msg);
		}
		finally
		{
			if (route.onClose)
				route.onClose(conn);
		}
	}

	/** 
	* Mount a static file directory at a specific URL path.
	*
	* Params:
	*   mountPath = URL path prefix (e.g., "/static", "/assets")
	*   rootPath = Filesystem directory path (e.g., "./public", "./assets")
	*   listDirectories = Whether to allow directory listing (default: false)
	*/
	void useStatic(string mountPath, string rootPath, bool listDirectories = false)
	{
		if (!mountPath.startsWith("/"))
			mountPath = "/" ~ mountPath;
		if (mountPath.endsWith("/") && mountPath.length > 1)
			mountPath = mountPath[0 .. $ - 1];

		staticMounts ~= StaticMount(mountPath, rootPath, listDirectories);
	}

	/** 
	* Set a GET method route with optional URL parameters.
	*
	* Params:
	*   path = The path pattern (e.g., "/users/:id" or "/users/:id/posts/:postId")
	*   handler = The handler/delegate for the route
	*/
	void get(string path, RouteHandler handler)
	{
		auto pattern = parseRoutePattern(path);
		routes ~= RoutePattern(
			pattern.pattern,
			pattern.paramNames,
			pattern.compiledRegex,
			handler,
			null, null, null, null,
			"GET"
		);
	}

	/** 
	* Set a POST method route with optional URL parameters.
	*
	* Params:
	*   path = The path pattern (e.g., "/users/:id" or "/api/data")
	*   handler = The handler/delegate for the route
	*/
	void post(string path, PostRouteHandler handler)
	{
		auto pattern = parseRoutePattern(path);
		routes ~= RoutePattern(
			pattern.pattern,
			pattern.paramNames,
			pattern.compiledRegex,
			null,
			handler,
			null, null, null,
			"POST"
		);
	}

	/** 
     * Parse route pattern to extract parameter names.
	 */
	private auto parseRoutePattern(string path)
	{
		string[] paramNames;
		string pattern = path;
		auto paramRegex = regex(r":([a-zA-Z_][a-zA-Z0-9_]*)");
		auto matches = matchAll(path, paramRegex);

		foreach (match; matches)
		{
			paramNames ~= match[1];
			pattern = pattern.replace(":" ~ match[1], "([^/]+)");
		}

		pattern = "^" ~ pattern ~ "$";
		auto compiledRegex = regex(pattern);

		return tuple!("pattern", "paramNames", "compiledRegex")(pattern, paramNames, compiledRegex);
	}

	/** 
	 * Get MIME type based on file extension.
	 */
	private string getMimeType(string filePath)
	{
		auto dotIndex = filePath.lastIndexOf('.');
		if (dotIndex == -1)
			return "application/octet-stream";
		auto ext = filePath[dotIndex .. $].toLower();
		if (auto mimeType = ext in mimeTypeCache)
			return *mimeType;
		return "application/octet-stream";
	}

	/** 
	 * Try to serve a static file.
	 */
	private Response tryServeStatic(string requestPath)
	{
		foreach (mount; staticMounts)
		{
			if (!requestPath.startsWith(mount.mountPath))
				continue;

			string relativePath = requestPath[mount.mountPath.length .. $];

			if (relativePath.startsWith("/"))
				relativePath = relativePath[1 .. $];

			string fullPath = buildPath(mount.rootPath, relativePath);
			string normalizedPath = buildNormalizedPath(fullPath);
			string normalizedRoot = buildNormalizedPath(mount.rootPath);

			if (!normalizedPath.startsWith(normalizedRoot))
				return Response("403 Forbidden", ResponseType.PLAINTEXT, 403);

			if (!exists(fullPath))
				continue;

			if (isDir(fullPath))
			{
				string indexPath = buildPath(fullPath, "index.html");
				if (exists(indexPath) && isFile(indexPath))
				{
					try
					{
						auto content = cast(ubyte[]) read(indexPath);
						auto response = Response(content, ResponseType.HTML);
						response.headers["Content-Type"] = "text/html";
						return response;
					}
					catch (Exception e)
						return Response("500 Internal Server Error", ResponseType.PLAINTEXT, 500);
				}
				else if (mount.listDirectories)
				{
					try
					{
						string listing = generateDirectoryListing(fullPath, requestPath);
						auto response = Response(listing, ResponseType.HTML);
						response.headers["Content-Type"] = "text/html";
						return response;
					}
					catch (Exception e)
						return Response("500 Internal Server Error", ResponseType.PLAINTEXT, 500);
				}
				else
				{
					return Response("403 Forbidden", ResponseType.PLAINTEXT, 403);
				}
			}
			else if (isFile(fullPath))
			{
				try
				{
					auto content = cast(ubyte[]) read(fullPath);
					string mimeType = getMimeType(fullPath);
					auto response = Response(content, ResponseType.BLOB);
					response.headers["Content-Type"] = mimeType;
					return response;
				}
				catch (Exception e)
				{
					return Response("500 Internal Server Error", ResponseType.PLAINTEXT, 500);
				}
			}
		}
		return Response("", ResponseType.PLAINTEXT, 404);
	}

	/** 
	 * Generate HTML directory listing.
	 */
	private string generateDirectoryListing(string dirPath, string urlPath)
	{
		auto entries = dirEntries(dirPath, SpanMode.shallow);
		string html = "<!DOCTYPE html><html><head><title>Directory: " ~ urlPath ~ "</title>";

		html ~= "<style>body{font-family:Arial,sans-serif;margin:40px;}";
		html ~= "a{text-decoration:none;color:#0066cc;}a:hover{text-decoration:underline;}";
		html ~= ".dir{font-weight:bold;}.file{color:#666;}</style></head><body>";
		html ~= "<h1>Index of " ~ urlPath ~ "</h1><hr><pre>";

		if (urlPath != "/" && urlPath.length > 1)
		{
			auto parentPath = urlPath.endsWith("/") ? urlPath[0 .. $ - 1] : urlPath;
			auto lastSlash = parentPath.lastIndexOf("/");
			if (lastSlash > 0)
				parentPath = parentPath[0 .. lastSlash];
			else
				parentPath = "/";
			html ~= "<a href=\"" ~ parentPath ~ "\">../</a>\n";
		}

		foreach (entry; entries)
		{
			string name = baseName(entry.name);
			string href = urlPath.endsWith("/") ? urlPath ~ name : urlPath ~ "/" ~ name;

			if (entry.isDir)
			{
				html ~= "<a href=\"" ~ href ~ "/\" class=\"dir\">" ~ name ~ "/</a>\n";
			}
			else
			{
				html ~= "<a href=\"" ~ href ~ "\" class=\"file\">" ~ name ~ "</a>\n";
			}
		}

		html ~= "</pre><hr></body></html>";
		return html;
	}

	private immutable string[int] statusMessages = [
		200: "OK",
		201: "Created",
		204: "No Content",
		301: "Moved Permanently",
		302: "Found",
		303: "See Other",
		304: "Not Modified",
		307: "Temporary Redirect",
		308: "Permanent Redirect",
		400: "Bad Request",
		401: "Unauthorized",
		403: "Forbidden",
		404: "Not Found",
		405: "Method Not Allowed",
		500: "Internal Server Error",
		502: "Bad Gateway",
		503: "Service Unavailable",
	];

	/**
	 * Get HTTP status message for status code.
	 */
	private string getStatusMessage(int statusCode) => statusMessages.get(statusCode, "Unknown");

	/** 
	 * Run the application.
	 */
	void run()
	{
		writeln("Go to http://localhost:8080");

		scope (exit)
		{
			running = false;
			server.close();
		}

		while (running)
		{
			try
			{
				auto client = server.accept();
				client.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, true);
				threadPool.addTask(client);
			}
			catch (Exception e)
			{
				if (running)
					writeln("Error accepting connection: ", e.msg);
			}
		}
	}

	/** 
	 * Handle some client.
	 */
	private void handleClient(Socket client)
	{
		bool isWebSocket = false;
		ubyte[8192] buffer;

		try
		{
			while (true)
			{
				size_t totalRead = 0;

				while (totalRead < cast(int) buffer.length - 1)
				{
					auto bytesRead = client.receive(buffer[totalRead .. $]);
					if (bytesRead <= 0)
						return;

					totalRead += bytesRead;
					auto chunk = cast(string) buffer[0 .. totalRead];
					if (chunk.canFind("\r\n\r\n"))
						break;
				}

				if (totalRead == 0)
					return;

				auto request = cast(string) buffer[0 .. totalRead];
				auto method = extractMethod(request);
				auto fullPath = extractPath(request);
				auto pathAndQuery = parsePathAndQuery(fullPath);
				auto requestBody = extractBody(request);
				auto context = RequestContext();

				context.query = pathAndQuery.query;
				context.body = requestBody;
				context.path = pathAndQuery.path;
				context.method = method;

				if (handleWebSocketUpgrade(client, request, pathAndQuery.path))
				{
					isWebSocket = true;
					return;
				}

				Response response = handleRoute(method, pathAndQuery.path, context);

				if (response.statusCode == 404 && method == "GET")
				{
					auto staticResponse = tryServeStatic(pathAndQuery.path);
					if (staticResponse.statusCode != 404)
						response = staticResponse;
				}

				bool keepAlive = request.toLower()
					.canFind("connection: keep-alive") &&
					response.statusCode < 400;

				sendResponse(client, response, keepAlive);

				if (!keepAlive)
					break;
			}
		}
		catch (Exception e)
		{
			try
			{
				auto errorResponse = Response("500 Internal Server Error", ResponseType.PLAINTEXT, 500);
				sendResponse(client, errorResponse, false);
			}
			catch (Exception)
			{
			}
		}
	}

	private void sendResponse(Socket client, Response response, bool keepAlive)
	{
		try
		{
			if (response.type == ResponseType.REDIRECT)
			{
				string location = response.headers.get("Location", "/");
				string statusMessage = getStatusMessage(response.statusCode);
				string responseHeader = "HTTP/1.1 " ~ to!string(response.statusCode) ~ " " ~ statusMessage ~ "\r\n" ~
					"Location: " ~ location ~ "\r\n" ~
					"Content-Length: 0\r\n";

				foreach (key, value; response.headers)
				{
					if (key != "Location")
						responseHeader ~= key ~ ": " ~ value ~ "\r\n";
				}

				responseHeader ~= (keepAlive ? "Connection: keep-alive\r\n\r\n"
						: "Connection: close\r\n\r\n");
				client.send(cast(ubyte[]) responseHeader);
			}
			else
			{
				string contentType = response.headers.get("Content-Type", getContentType(
						response.type
				));
				string statusMessage = getStatusMessage(response.statusCode);
				string responseHeader = "HTTP/1.1 " ~ to!string(
					response.statusCode) ~ " " ~ statusMessage ~ "\r\n" ~
					"Content-Type: " ~ contentType ~ "\r\n" ~
					"Content-Length: " ~ to!string(
						response.content.length
					) ~ "\r\n";

				foreach (key, value; response.headers)
				{
					if (key != "Content-Type")
						responseHeader ~= key ~ ": " ~ value ~ "\r\n";
				}

				responseHeader ~= (keepAlive ? "Connection: keep-alive\r\n\r\n"
						: "Connection: close\r\n\r\n");

				client.send(cast(ubyte[]) responseHeader);

				if (response.content.length > 0)
					client.send(response.content);
			}
		}
		catch (Exception e)
		{
			writeln("Error sending response: ", e.msg);
		}
	}

	/** 
	 * Parse path and query parameters
	 */
	private auto parsePathAndQuery(string fullPath)
	{
		string[string] queryParams;
		string path = fullPath;
		auto queryIndex = fullPath.indexOf("?");

		if (queryIndex != -1)
		{
			path = fullPath[0 .. queryIndex];
			auto queryString = fullPath[queryIndex + 1 .. $];

			foreach (param; queryString.split("&"))
			{
				auto equalIndex = param.indexOf("=");
				if (equalIndex != -1)
				{
					auto key = param[0 .. equalIndex];
					auto value = param[equalIndex + 1 .. $];
					queryParams[key] = value;
				}
				else
					queryParams[param] = "";

			}
		}

		return tuple!("path", "query")(path, queryParams);
	}

	/** 
	 * Get content type based on response type
	 */
	private string getContentType(ResponseType type)
	{
		switch (type)
		{
		case ResponseType.JSON:
			return "application/json";
		case ResponseType.PLAINTEXT:
			return "text/plain";
		case ResponseType.BLOB:
			return "application/octet-stream";
		case ResponseType.REDIRECT:
			return "text/html";
		case ResponseType.HTML:
		default:
			return "text/html";
		}
	}

	/** 
	 * Extract the HTTP method from the request.
	 */
	private string extractMethod(string request)
	{
		auto i = request.indexOf(" ");
		if (i == -1)
			return "GET";
		return request[0 .. i];
	}

	/** 
	 * Extract the path given some URI request in string form.
	 */
	private string extractPath(string request)
	{
		auto i = request.indexOf("\r\n");
		if (i == -1)
			return "/";
		auto requestLine = request[0 .. i].split();
		return requestLine.length >= 2 ? requestLine[1] : "/";
	}

	/** 
	 * Register PUT path.
	 */
	void put(string path, PutRouteHandler handler)
	{
		auto pattern = parseRoutePattern(path);
		routes ~= RoutePattern(
			pattern.pattern,
			pattern.paramNames,
			pattern.compiledRegex,
			null, null,
			handler,
			null, null,
			"PUT"
		);
	}

	/** 
	 * Register PATCH path.
	 */
	void patch(string path, PatchRouteHandler handler)
	{
		auto pattern = parseRoutePattern(path);
		routes ~= RoutePattern(
			pattern.pattern,
			pattern.paramNames,
			pattern.compiledRegex,
			null, null, null,
			handler,
			null,
			"PATCH"
		);
	}

	/** 
	 * Register DELETE path.
	 */
	void del(string path, DeleteRouteHandler handler)
	{
		auto pattern = parseRoutePattern(path);
		routes ~= RoutePattern(
			pattern.pattern,
			pattern.paramNames,
			pattern.compiledRegex,
			null, null, null, null,
			handler,
			"DELETE"
		);
	}

	/** 
	 * Extract the request body from a POST request.
	 */
	private string extractBody(string request)
	{
		auto headerEnd = request.indexOf("\r\n\r\n");
		if (headerEnd == -1)
			return "";
		return request[headerEnd + 4 .. $];
	}

	/** 
	 * Handle the route based on method and path with parameter matching.
	 */
	private Response handleRoute(string method, string path, ref RequestContext context)
	{
		foreach (route; routes)
		{
			if (route.method != method)
				continue;

			auto routeRegex = regex(route.pattern);
			auto match = matchFirst(path, routeRegex);

			if (match)
			{
				for (size_t i = 0; i < route.paramNames.length && i + 1 < match.length;
					i++)
					context.params[route.paramNames[i]] = match[i + 1];

				final switch (method)
				{
				case "GET":
					return route.handler(context);
				case "POST":
					return route.postHandler(context);
				case "PUT":
					return route.putHandler(context);
				case "PATCH":
					return route.patchHandler(context);
				case "DELETE":
					return route.deleteHandler(context);
				}
			}
		}
		return Response("404 Not Found", ResponseType.PLAINTEXT, 404);
	}
}

Response html(string content) => Response(content, ResponseType.HTML);
Response json(string content) => Response(content, ResponseType.JSON);
Response text(string content) => Response(content, ResponseType.PLAINTEXT);
Response blob(ubyte[] content) => Response(content, ResponseType.BLOB);
Response blob(string content) => Response(cast(ubyte[]) content, ResponseType.BLOB);
Response redirect(string location, int statusCode = 302)
{
	auto response = Response("", ResponseType.REDIRECT, statusCode);
	response.headers["Location"] = location;
	return response;
}

Response permanentRedirect(string location) => redirect(location, 301);
Response temporaryRedirect(string location) => redirect(location, 302);
Response seeOther(string location) => redirect(location, 303);

unittest
{
	auto app = new PrismApplication();

	app.useStatic("/static", "./public");
	app.useStatic("/assets", "./assets", true);
	app.useStatic("/downloads", "./files");

	app.get("/", (context) => html(
			`<html><body>
				<h1>Welcome to D Prism Framework</h1>
				<p><a href="/static/">Static Files</a></p>
				<p><a href="/assets/">Assets (with listing)</a></p>
				<p><a href="/downloads/">Downloads</a></p>
				<p><a href="/chat">WebSocket Chat Room</a></p>
			</body></html>`)
	);

	app.get("/chat", (context) => html(
			`<!DOCTYPE html>
		<html>
		<head>
			<title>Prism Chat Room</title>
			<style>
				body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
				.chat-messages { height: 400px; overflow-y: auto; padding: 20px; border-bottom: 1px solid #eee; }
				.message { margin: 10px 0; padding: 10px; border-radius: 5px; }
				.message.own { background: #007bff; color: white; text-align: right; }
				.message.other { background: #e9ecef; }
				.message .username { font-weight: bold; font-size: 0.9em; margin-bottom: 5px; }
				.message .text { margin: 0; }
				.chat-input { padding: 20px; display: flex; gap: 10px; }
				.chat-input button:hover { background: #0056b3; }
				.username-input { padding: 20px; background: #f8f9fa; border-radius: 0 0 8px 8px; }
			</style>
		</head>
		<body>
			<div class="chat-container">
				<div class="chat-header">
					<h1>Prism WebSocket Chat Room</h1>
				</div>
				
				<div id="usernameSection" class="username-input">
					<label>Enter your username: </label>
					<input type="text" id="usernameInput" placeholder="Your username" maxlength="20">
					<button onclick="setUsername()">Join Chat</button>
				</div>
				
				<div id="chatSection" style="display: none;">
					<div id="messages" class="chat-messages"></div>
					<div class="chat-input">
						<input type="text" id="messageInput" placeholder="Type your message..." maxlength="500">
						<button onclick="sendMessage()">Send</button>
					</div>
					<div id="status" class="status">Disconnected</div>
				</div>
			</div>

			<script>
				let ws = null;
				let username = '';
				let isConnected = false;

				function setUsername() {
					const input = document.getElementById('usernameInput');
					const name = input.value.trim();
					
					if (name.length < 2) {
						alert('Username must be at least 2 characters long');
						return;
					}
					
					username = name;
					document.getElementById('usernameSection').style.display = 'none';
					document.getElementById('chatSection').style.display = 'block';
					connectWebSocket();
				}

				function connectWebSocket() {
					const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
					const wsUrl = protocol + '//' + window.location.host + '/ws/chat';
					
					ws = new WebSocket(wsUrl);
					
					ws.onopen = function() {
						isConnected = true;
						updateStatus('Connected as ' + username);
						
						ws.send(JSON.stringify({
							type: 'join',
							username: username,
							message: username + ' joined the chat'
						}));
					};
					
					ws.onmessage = function(event) {
						try {
							const data = JSON.parse(event.data);
							addMessage(data.username, data.message, data.username === username);
						} catch (e) {
							console.error('Failed to parse message:', e);
						}
					};
					
					ws.onclose = function() {
						isConnected = false;
						updateStatus('Disconnected - trying to reconnect...');
						setTimeout(connectWebSocket, 3000);
					};
					
					ws.onerror = function(error) {
						console.error('WebSocket error:', error);
						updateStatus('Connection error');
					};
				}

				function sendMessage() {
					const input = document.getElementById('messageInput');
					const message = input.value.trim();
					
					if (!message || !isConnected) return;
					
					ws.send(JSON.stringify({
						type: 'message',
						username: username,
						message: message
					}));
					
					input.value = '';
				}

				function addMessage(user, text, isOwn) {
					const messagesDiv = document.getElementById('messages');
					const messageDiv = document.createElement('div');
					messageDiv.className = 'message ' + (isOwn ? 'own' : 'other');
					
					messageDiv.innerHTML = 
						'<div class="username">' + escapeHtml(user) + ':</div>' +
						'<div class="text">' + escapeHtml(text) + '</div>';
					
					messagesDiv.appendChild(messageDiv);
					messagesDiv.scrollTop = messagesDiv.scrollHeight;
				}

				function updateStatus(status) {
					document.getElementById('status').textContent = status;
				}

				function escapeHtml(text) {
					const div = document.createElement('div');
					div.textContent = text;
					return div.innerHTML;
				}

				document.getElementById('messageInput').addEventListener('keypress', function(e) {
					if (e.key === 'Enter') {
						sendMessage();
					}
				});
				document.getElementById('usernameInput').addEventListener('keypress', function(e) {
					if (e.key === 'Enter') {
						setUsername();
					}
				});
			</script>
		</body>
		</html>`
	));

	WebSocketConnection[] chatConnections;

	app.websocket("/ws/chat",
		(WebSocketConnection conn) {
		chatConnections ~= conn;
		writeln("Client connected to chat. Total connections: ", chatConnections.length);
	},
		(WebSocketConnection conn, string message) {
		writeln("Received chat message: ", message);

		foreach (client; chatConnections)
		{
			if (client.isConnectionOpen())
			{
				try
				{
					client.sendText(message);
				}
				catch (Exception e)
				{
					writeln("Failed to send message to client: ", e.msg);
				}
			}
		}

		import std.algorithm : filter;
		import std.array : array;

		chatConnections = chatConnections.filter!(c => c.isConnectionOpen()).array;
	},
		(WebSocketConnection conn, ubyte[] data) {
		writeln("Received binary data in chat: ", data.length, " bytes");
	},
		(WebSocketConnection conn) {
		writeln("Chat client disconnected");

		import std.algorithm : filter;
		import std.array : array;

		chatConnections = chatConnections.filter!(c => c !is conn).array;
		writeln("Total connections: ", chatConnections.length);
	}
	);

	app.get("/about", (context) => html("<html><body><h1>About Page</h1></body></html>"));

	app.get("/users/:id", (context) {
		auto userId = context.params.get("id", "unknown");
		return html("<html><body><h1>User Profile</h1><p>User ID: " ~ userId ~ "</p></body></html>");
	});

	app.get("/users/:userId/posts/:postId", (context) {
		auto userId = context.params.get("userId", "unknown");
		auto postId = context.params.get("postId", "unknown");
		return html(
			"<html><body><h1>User Post</h1><p>User: " ~ userId ~ ", Post: " ~ postId ~ "</p></body></html>");
	});

	app.get("/search", (context) {
		auto query = context.query.get("q", "");
		auto page = context.query.get("page", "1");
		return html(
			"<html><body><h1>Search Results</h1><p>Query: " ~ query ~ ", Page: " ~ page ~ "</p></body></html>");
	});

	app.get("/api/users/:id", (context) {
		auto userId = context.params.get("id", "0");
		return json(`{"id": "` ~ userId ~ `", "name": "John Doe", "email": "john@example.com"}`);
	});

	app.get("/ping", (context) => text("pong"));

	app.post("/api/users", (context) {
		return json(`{"status": "success", "message": "User created", "data": ` ~ context.body ~ `}`);
	});

	app.post("/users/:id/update", (context) {
		auto userId = context.params.get("id", "unknown");
		return json(
			`{"status": "success", "message": "User ` ~ userId ~ ` updated", "data": ` ~ context.body ~ `}`);
	});

	app.put("/api/users/:id", (context) {
		auto userId = context.params.get("id", "unknown");
		return json(
			`{"status": "success", "message": "User ` ~ userId ~ ` fully updated", "data": ` ~ context.body ~ `}`);
	});

	app.patch("/api/users/:id", (context) {
		auto userId = context.params.get("id", "unknown");
		return json(
			`{"status": "success", "message": "User ` ~ userId ~ ` partially updated", "changes": ` ~ context.body ~ `}`);
	});

	app.del("/api/users/:id", (context) {
		auto userId = context.params.get("id", "unknown");
		return json(`{"status": "success", "message": "User ` ~ userId ~ ` deleted"}`);
	});

	app.get("/download", (context) {
		auto fileContent = cast(ubyte[]) "This is binary data";
		return blob(fileContent);
	});

	app.run();
}
