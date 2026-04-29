package server

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
)

func newReverseProxy(targetURL string) http.Handler {
	parsed := toHTTPURL(targetURL)
	target, _ := url.Parse(parsed)
	proxy := httputil.NewSingleHostReverseProxy(target)
	// op-reth's JSON-RPC server validates the Host header against an allowlist
	// (default: 127.0.0.1, localhost). NewSingleHostReverseProxy preserves
	// req.Host from the incoming request, which is "localhost:8547" here and
	// gets rejected. Force it to match the upstream.
	defaultDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		defaultDirector(req)
		req.Host = target.Host
	}
	return proxy
}

func toHTTPURL(raw string) string {
	if strings.HasPrefix(raw, "ws://") {
		return "http://" + strings.TrimPrefix(raw, "ws://")
	}
	if strings.HasPrefix(raw, "wss://") {
		return "https://" + strings.TrimPrefix(raw, "wss://")
	}
	return raw
}
