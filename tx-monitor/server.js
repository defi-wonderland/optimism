const express = require("express");
const cors = require("cors");
const { createProxyMiddleware } = require("http-proxy-middleware");
const path = require("path");

const app = express();
const PORT = 3000;

// Enable CORS for all routes
app.use(cors());

// Serve static files
app.use(express.static(__dirname));

// Proxy for L1 RPC
app.use(
  "/api/l1",
  createProxyMiddleware({
    target: "http://127.0.0.1:8544",
    changeOrigin: true,
    pathRewrite: {
      "^/api/l1": "",
    },
    onProxyReq: (proxyReq, req, res) => {
      console.log("L1 RPC request:", req.method, req.url);
    },
    onError: (err, req, res) => {
      console.error("L1 RPC proxy error:", err);
      res.status(500).json({ error: "L1 RPC unavailable" });
    },
  })
);

// Proxy for L2 RPC
app.use(
  "/api/l2",
  createProxyMiddleware({
    target: "http://127.0.0.1:8545",
    changeOrigin: true,
    pathRewrite: {
      "^/api/l2": "",
    },
    onProxyReq: (proxyReq, req, res) => {
      console.log("L2 RPC request:", req.method, req.url);
    },
    onError: (err, req, res) => {
      console.error("L2 RPC proxy error:", err);
      res.status(500).json({ error: "L2 RPC unavailable" });
    },
  })
);

// Default route
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

app.listen(PORT, () => {
  console.log(`🚀 Transaction Monitor running on http://localhost:${PORT}`);
  console.log("📡 L1 RPC proxied to http://127.0.0.1:8544");
  console.log("📡 L2 RPC proxied to http://127.0.0.1:8545");
});
