module prism.server;

import std;

/** 
 * Response type enumeration
 */
enum ResponseType
{
	HTML,
	JSON,
	PLAINTEXT,
	BLOB
}

/** 
 * Response structure containing content and type
 */
struct Response
{
	ubyte[] content;
	ResponseType type;
	string[string] headers;

	this(ubyte[] content, ResponseType type = ResponseType.HTML)
	{
		this.content = content;
		this.type = type;
	}

	this(string content, ResponseType type = ResponseType.HTML)
	{
		this(cast(ubyte[]) content, type);
	}
}

/** 
 * Request context containing path parameters and query parameters
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
 * Route handlers that can return different response types
 */
alias RouteHandler = Response delegate(RequestContext context);
alias PostRouteHandler = Response delegate(RequestContext context);
alias PutRouteHandler = Response delegate(RequestContext context);
alias PatchRouteHandler = Response delegate(RequestContext context);
alias DeleteRouteHandler = Response delegate(RequestContext context);

/** 
 * Route pattern structure to handle parameterized routes
 */
struct RoutePattern
{
	string pattern;
	string[] paramNames;
	RouteHandler handler;
	PostRouteHandler postHandler;
	PutRouteHandler putHandler;
	PatchRouteHandler patchHandler;
	DeleteRouteHandler deleteHandler;
	string method;
}

/** 
 * Static file mount configuration
 */
struct StaticMount
{
	string mountPath;
	string rootPath;
	bool listDirectories = false;
}

/** 
 * The application itself.
 */
class PrismApplication
{
	private TcpSocket server;
	private RoutePattern[] routes;
	private StaticMount[] staticMounts;

	/** 
	* Instantiate a new application.
	*
	* Params:
	*   port = Port to operate on
	*/
	this(ushort port = 8080)
	{
		server = new TcpSocket();
		server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		server.bind(new InternetAddress(port));
		server.listen(1000);
	}

	/** 
	* Mount a static file directory at a specific URL path.
	*
	* Params:
	*   mountPath = URL path prefix (e.g., "/static", "/assets")
	*   rootPath = Filesystem directory path (e.g., "./public", "./assets")
	*   listDirectories = Whether to allow directory listing (default: false)
	*/
	void serveStatic(string mountPath, string rootPath, bool listDirectories = false)
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
			handler,
			null,
			null,
			null,
			null,
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
			null,
			handler,
			null,
			null,
			null,
			"POST"
		);
	}
	/** 
	* Parse route pattern to extract parameter names
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

		return tuple!("pattern", "paramNames")(pattern, paramNames);
	}

	/** 
	* Get MIME type based on file extension
	*/
	private string getMimeType(string filePath)
	{
		auto ext = filePath.toLower();
		if (ext.endsWith(".html") || ext.endsWith(".htm"))
			return "text/html";
		else if (ext.endsWith(".css"))
			return "text/css";
		else if (ext.endsWith(".js"))
			return "application/javascript";
		else if (ext.endsWith(".json"))
			return "application/json";
		else if (ext.endsWith(".png"))
			return "image/png";
		else if (ext.endsWith(".jpg") || ext.endsWith(".jpeg"))
			return "image/jpeg";
		else if (ext.endsWith(".gif"))
			return "image/gif";
		else if (ext.endsWith(".svg"))
			return "image/svg+xml";
		else if (ext.endsWith(".ico"))
			return "image/x-icon";
		else if (ext.endsWith(".pdf"))
			return "application/pdf";
		else if (ext.endsWith(".txt"))
			return "text/plain";
		else if (ext.endsWith(".xml"))
			return "application/xml";
		else
			return "application/octet-stream";
	}

	/** 
	* Try to serve a static file
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
			{
				return Response("403 Forbidden", ResponseType.PLAINTEXT);
			}

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
						return Response("500 Internal Server Error", ResponseType.PLAINTEXT);
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
						return Response("500 Internal Server Error", ResponseType.PLAINTEXT);
				}
				else
				{
					return Response("403 Forbidden", ResponseType.PLAINTEXT);
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
					return Response("500 Internal Server Error", ResponseType.PLAINTEXT);
				}
			}
		}
		return Response("", ResponseType.PLAINTEXT);
	}

	/** 
	* Generate HTML directory listing
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

	/** 
	* Run the application.
	*/
	void run()
	{
		writeln("Go to http://localhost:8080");

		scope (exit)
			server.close();

		while (true)
		{
			auto client = server.accept();

			client.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, true);
			client.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(5));

			void handleClient(Socket client)
			{
				scope (exit)
					client.close();

				while (true)
				{
					ubyte[4096] buffer;
					size_t totalRead = 0;

					while (true)
					{
						auto bytesRead = client.receive(buffer[totalRead .. $]);
						if (bytesRead <= 0)
							return;
						totalRead += bytesRead;
						auto chunk = cast(string) buffer[0 .. totalRead];
						if (chunk.canFind("\r\n\r\n"))
							break;
					}

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

					Response response;

					response = handleRoute(method, pathAndQuery.path, context);

					if (response.content == cast(ubyte[]) "404 Not Found" && method == "GET")
					{
						auto staticResponse = tryServeStatic(pathAndQuery.path);
						if (staticResponse.content.length > 0)
							response = staticResponse;
					}

					bool keepAlive = request.toLower().canFind("connection: keep-alive");
					string contentType = response.headers.get("Content-Type", getContentType(
							response.type));

					string responseHeader = "HTTP/1.1 200 OK\r\n"
						~ "Content-Type: " ~ contentType ~ "\r\n"
						~ "Content-Length: " ~ to!string(response.content.length) ~ "\r\n";

					foreach (key, value; response.headers)
					{
						if (key != "Content-Type")
							responseHeader ~= key ~ ": " ~ value ~ "\r\n";
					}

					responseHeader ~= (keepAlive ? "Connection: keep-alive\r\n\r\n"
							: "Connection: close\r\n\r\n");

					client.send(cast(ubyte[]) responseHeader);
					client.send(response.content);

					if (!keepAlive)
						break;
				}
			}

			handleClient(client);
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
				{
					queryParams[param] = "";
				}
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
		routes ~= RoutePattern(pattern.pattern, pattern.paramNames, null, null, handler, null, null, "PUT");
	}

	/** 
	 * Register PATCH path.
	 */
	void patch(string path, PatchRouteHandler handler)
	{
		auto pattern = parseRoutePattern(path);
		routes ~= RoutePattern(pattern.pattern, pattern.paramNames, null, null, null, handler, null, "PATCH");
	}

	/** 
	 * Register DELETE path.
	 */
	void del(string path, DeleteRouteHandler handler)
	{
		auto pattern = parseRoutePattern(path);
		routes ~= RoutePattern(pattern.pattern, pattern.paramNames, null, null, null, null, handler, "DELETE");
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
		return Response("404 Not Found", ResponseType.PLAINTEXT);
	}

}

Response html(string content) => Response(content, ResponseType.HTML);
Response json(string content) => Response(content, ResponseType.JSON);
Response text(string content) => Response(content, ResponseType.PLAINTEXT);
Response blob(ubyte[] content) => Response(content, ResponseType.BLOB);
Response blob(string content) => Response(cast(ubyte[]) content, ResponseType.BLOB);

unittest
{
	auto app = new PrismApplication();

	app.serveStatic("/static", "./public");
	app.serveStatic("/assets", "./assets", true);
	app.serveStatic("/downloads", "./files");

	app.get("/", (context) => html(
			`<html><body>
				<h1>Welcome to D Prism Framework</h1>
				<p><a href="/static/">Static Files</a></p>
				<p><a href="/assets/">Assets (with listing)</a></p>
				<p><a href="/downloads/">Downloads</a></p>
			</body></html>`)
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
