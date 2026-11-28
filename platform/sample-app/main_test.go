package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func get(t *testing.T, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	newMux("v1").ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestHealthz(t *testing.T) {
	rec := get(t, "/healthz")
	if rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != "ok" {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
}

func TestRootShowsVersion(t *testing.T) {
	rec := get(t, "/")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "v1") {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
}

func TestUnknownPathIs404(t *testing.T) {
	if rec := get(t, "/nope"); rec.Code != http.StatusNotFound {
		t.Fatalf("got %d", rec.Code)
	}
}
