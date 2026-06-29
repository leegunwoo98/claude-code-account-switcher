//go:build !darwin

package credstore

import "testing"

func TestFileStoreRoundTrip(t *testing.T) {
	t.Setenv("CLAUDE_SUBSCRIPTIONS_DIR", t.TempDir())

	if v, err := Get("svc-a"); err != nil || v != "" {
		t.Fatalf("Get on empty store = %q, %v; want empty, nil", v, err)
	}
	if err := Set("svc-a", "sk-ant-oat-AAA"); err != nil {
		t.Fatal(err)
	}
	if err := Set("svc-b", "sk-ant-oat-BBB"); err != nil {
		t.Fatal(err)
	}
	if v, _ := Get("svc-a"); v != "sk-ant-oat-AAA" {
		t.Errorf("Get svc-a = %q", v)
	}
	if err := Delete("svc-a"); err != nil {
		t.Fatal(err)
	}
	if v, _ := Get("svc-a"); v != "" {
		t.Errorf("after delete, Get svc-a = %q, want empty", v)
	}
	if v, _ := Get("svc-b"); v != "sk-ant-oat-BBB" {
		t.Errorf("svc-b should survive deletion of svc-a, got %q", v)
	}
}
