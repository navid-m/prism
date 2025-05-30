## Features

-  Route matching with path parameters (e.g. `/users/:id`)
-  Basic request parsing (method, path, query, body)
-  Simple response types (`HTML`, `JSON`, `TEXT`)
-  Supports `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`
-  No external dependencies besides the D stdlib.

## Getting Started

```d
auto app = new PrismApplication();

app.get("/", (context) => html("<h1>Hello</h1>"));

app.post("/submit", (context) => json(`{"received": true}`));

app.run();
```

Visit `http://localhost:8080` in your browser.

## Route Parameters

Supports routes like:

```d
app.get("/users/:id", (context) {
    auto id = context.params["id"];
    return text("User ID: " ~ id);
});
```

## Query Parameters

```d
app.get("/search", (context) {
    auto q = context.query.get("q", "");
    return text("Search query: " ~ q);
});
```

## Response Helpers

```d
html("<h1>HTML</h1>");
json(`{"key": "value"}`);
text("Plain text");
```

---

Navid M © 2025

No warranty. Not ever.
