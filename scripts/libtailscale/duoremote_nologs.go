// Copied into libtailscale by scripts/build-tailscalekit.sh.

package main

import "os"

// DuoRemote sends nothing to Tailscale's log service: no accounts, analytics or servers of
// its own. Go reads the environment when the library loads, so this must be set from Go.
func init() {
	os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true")
}
