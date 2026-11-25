package main

import "runtime/debug"

// Set only by the release build; local developer builds remain identifiable.
var releaseID = "development"
var sourceCommit = "unknown"

func buildInfo() map[string]string {
	info := map[string]string{"release": releaseID, "sourceCommit": sourceCommit}
	if build, ok := debug.ReadBuildInfo(); ok {
		info["goVersion"] = build.GoVersion
		for _, dep := range build.Deps {
			if dep.Path == "tailscale.com" && dep.Replace == nil {
				info["tailscaleVersion"] = dep.Version
			}
		}
	}
	return info
}
