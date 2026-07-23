package httpmw

import "testing"

func TestNormalizePath(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		// Routes statiques — inchangées.
		{"/api/auth/login", "/api/auth/login"},
		{"/api/auth/register", "/api/auth/register"},
		{"/api/users/me", "/api/users/me"},
		{"/api/streams", "/api/streams"},
		{"/api/broadcaster-requests/me", "/api/broadcaster-requests/me"},
		{"/api/admin/broadcaster-requests", "/api/admin/broadcaster-requests"},

		// Segments dynamiques — bornés au pattern de route.
		{"/api/streams/3f2a8c1e-0b7d-4e2f-9a51-6c8d0e4b7f21", "/api/streams/{id}"},
		{"/api/streams/3f2a8c1e-0b7d-4e2f-9a51-6c8d0e4b7f21/start", "/api/streams/{id}/start"},
		{"/api/streams/abc/stop", "/api/streams/{id}/stop"},
		{"/api/streams/abc/events", "/api/streams/{id}/events"},
		{"/api/streams/abc/playlist.m3u8", "/api/streams/{id}/playlist.m3u8"},
		{"/api/streams/abc/segments/seg00042.ts", "/api/streams/{id}/segments/{segment}"},
		{"/api/streams/ingest/SECRETKEY123", "/api/streams/ingest/{stream_key}"},
		{"/api/admin/users/64c832e6-9e5d-4300-afb8-d1a4c2bd17ef", "/api/admin/users/{id}"},
		{"/api/admin/broadcaster-requests/42/approve", "/api/admin/broadcaster-requests/{id}/approve"},
		{"/api/admin/broadcaster-requests/42/reject", "/api/admin/broadcaster-requests/{id}/reject"},

		// Hors table (bots, typos, swagger) — une seule série.
		{"/wp-admin/setup.php", "{other}"},
		{"/api/streams/abc/unknown-sub", "{other}"},
		{"/favicon.ico", "{other}"},
		{"/", "{other}"},
		{"/swagger/index.html", "{other}"},
	}
	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			if got := normalizePath(tc.in); got != tc.want {
				t.Errorf("normalizePath(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
