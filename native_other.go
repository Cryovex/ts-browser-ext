//go:build !windows

package main

func registerNativeHost(browserByte, manifestPath string) error   { return nil }
func unregisterNativeHost(browserByte, manifestPath string) error { return nil }
