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
