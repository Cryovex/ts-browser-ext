package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

func frame(v any) []byte {
	b, _ := json.Marshal(v)
	var out bytes.Buffer
	binary.Write(&out, binary.LittleEndian, uint32(len(b)))
	out.Write(b)
	return out.Bytes()
}

type interleavingWriter struct {
	bytes.Buffer
	onHeader func()
}

func (w *interleavingWriter) Write(p []byte) (int, error) {
	if w.onHeader != nil {
		f := w.onHeader
		w.onHeader = nil
		f() // Simulate an input read while an output header is in flight.
	}
	return w.Buffer.Write(p)
}

func TestSendHeaderIndependentOfRead(t *testing.T) {
	out := &interleavingWriter{}
	h := newHost(bytes.NewReader(frame(request{Cmd: CmdGetStatus})), out)
	h.logf = func(string, ...any) {}
	out.onHeader = func() {
		if _, err := h.readMessage(); err != nil {
			t.Fatal(err)
		}
	}
	if err := h.send(&reply{Init: &initResult{}}); err != nil {
		t.Fatal(err)
	}
	b := out.Bytes()
	if n := int(binary.LittleEndian.Uint32(b[:4])); n != len(b)-4 {
		t.Fatalf("corrupt frame: header=%d payload=%d", n, len(b)-4)
	}
}

func TestConcurrentRepliesStayFramed(t *testing.T) {
	var out bytes.Buffer
	h := newHost(bytes.NewReader(nil), &out)
	h.logf = func(string, ...any) {}
	var wg sync.WaitGroup
	const count = 200
	for i := range count {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if err := h.send(&reply{Init: &initResult{Error: fmt.Sprintf("reply-%d", i)}}); err != nil {
				t.Error(err)
			}
		}(i)
	}
	wg.Wait()
	seen := map[string]bool{}
	for range count {
		var n uint32
		if err := binary.Read(&out, binary.LittleEndian, &n); err != nil {
			t.Fatal(err)
		}
		if n > maxMsgSize {
			t.Fatalf("invalid length %d", n)
		}
		b := make([]byte, n)
		if _, err := io.ReadFull(&out, b); err != nil {
			t.Fatal(err)
		}
		var msg reply
		if err := json.Unmarshal(b, &msg); err != nil {
			t.Fatal(err)
		}
		if msg.Init == nil {
			t.Fatal("missing init result")
		}
		seen[msg.Init.Error] = true
	}
	if len(seen) != count || out.Len() != 0 {
		t.Fatal("lost or duplicated messages")
	}
}

func TestNativeManifestEscapesWindowsPath(t *testing.T) {
	const binaryPath = `C:\Users\A "quoted" name\Native Host\ts-browser-ext.exe`
	b, err := nativeManifest("F", "ts-browser-ext@cryovex", binaryPath)
	if err != nil {
		t.Fatal(err)
	}
	var manifest struct {
		Path       string   `json:"path"`
		Extensions []string `json:"allowed_extensions"`
	}
	if err := json.Unmarshal(b, &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.Path != binaryPath || len(manifest.Extensions) != 1 || manifest.Extensions[0] != "ts-browser-ext@cryovex" {
		t.Fatalf("invalid manifest: %s", b)
	}
}

func TestSettingsBeforeInit(t *testing.T) {
	h := newHost(bytes.NewReader(nil), io.Discard)
	w := httptest.NewRecorder()
	h.httpProxyHandler().ServeHTTP(w, httptest.NewRequest(http.MethodGet, "http://100.100.100.100/", nil))
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d", w.Code)
	}
}

func TestInvalidInstallArguments(t *testing.T) {
	for _, arg := range []string{"", "F", "C", "Xabc", "Cbad", "Fbad\nID"} {
		if err := install(arg); err == nil {
			t.Errorf("accepted invalid argument %q", arg)
		}
	}
}
