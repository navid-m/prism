## Usage

```d
import prism.server;

auto app = new PrismApplication();

app.get("/", (context) => html("<h1>Hello</h1>"));

app.post("/submit", (context) => json(`{"received": true}`));

app.run();
```

## Features

-  Fluent and intuitive URL routing
-  WebSockets support
-  Context actions, redirects, etc...
-  Static file server middleware
-  Full support for HTTP methods: GET, POST, PUT, PATCH, DELETE
-  Automatic handling of all MIME types

## Concurrency Benchmark

Achieves sub-1ms latency on average for approx. 14,000 concurrent requests from 250 virtual users.

```
✓ status was 200

  checks.........................: 100.00% ✓ 13650      ✗ 0
  data_received..................: 4.9 MB  121 kB/s
  data_sent......................: 1.1 MB  27 kB/s
  http_req_blocked...............: avg=540.99µs min=0s       med=508.4µs  max=3.28ms   p(90)=1.28ms   p(95)=1.65ms
  http_req_connecting............: avg=525.85µs min=0s       med=507.1µs  max=3.28ms   p(90)=1.25ms   p(95)=1.63ms
  http_req_duration..............: avg=576.31µs min=0s       med=525µs    max=3.8ms    p(90)=1.54ms   p(95)=1.65ms
    { expected_response:true }...: avg=576.31µs min=0s       med=525µs    max=3.8ms    p(90)=1.54ms   p(95)=1.65ms
  http_req_failed................: 0.00%   ✓ 0          ✗ 13650
  http_req_receiving.............: avg=82.37µs  min=0s       med=0s       max=1.53ms   p(90)=520.2µs  p(95)=531.9µs
  http_req_sending...............: avg=22.73µs  min=0s       med=0s       max=1.62ms   p(90)=0s       p(95)=0s
  http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s       p(90)=0s       p(95)=0s
  http_req_waiting...............: avg=471.19µs min=0s       med=507.6µs  max=3.23ms   p(90)=1.1ms    p(95)=1.57ms
  http_reqs......................: 13650   338.231292/s
  iteration_duration.............: avg=508.57ms min=500.01ms med=508.58ms max=522.47ms p(90)=511.09ms p(95)=513.13ms
  iterations.....................: 13650   338.231292/s
✓ latency_8001...................: avg=576.31µs min=0s       med=525µs    max=3.8ms    p(90)=1.54ms   p(95)=1.65ms
✓ success_8001...................: 100.00% ✓ 13650      ✗ 0
  vus............................: 7       min=7        max=250
  vus_max........................: 250     min=250      max=250


running (0m40.4s), 000/250 VUs, 13650 complete and 0 interrupted iterations
default ✓ [======================================] 000/250 VUs  40s
```

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

## Response Types

```d
html("<h1>HTML</h1>");
json(`{"key": "value"}`);
text("Plain text");
blob([0x42, 0x69, 0x6E, 0x61, 0x72, 0x79]);
```

---

Navid M © 2025

No warranty. Not ever.
