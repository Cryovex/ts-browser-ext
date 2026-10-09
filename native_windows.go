//go:build windows

package main

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows/registry"
)

func nativeRegistryPath(browserByte string) string {
	if browserByte == "F" {
		return `Software\Mozilla\NativeMessagingHosts\` + nativeHostName(browserByte)
	}
	return `Software\Google\Chrome\NativeMessagingHosts\` + nativeHostName(browserByte)
}

func registerNativeHost(browserByte, manifestPath string) error {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, nativeRegistryPath(browserByte), registry.SET_VALUE)
	if err != nil {
		return fmt.Errorf("register native host: %w", err)
	}
	defer k.Close()
	return k.SetStringValue("", manifestPath)
}

func unregisterNativeHost(browserByte, manifestPath string) error {
	keyPath := nativeRegistryPath(browserByte)
	k, err := registry.OpenKey(registry.CURRENT_USER, keyPath, registry.QUERY_VALUE)
	if errors.Is(err, registry.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	registered, _, err := k.GetStringValue("")
	k.Close()
	if err != nil {
		return err
	}
	if !strings.EqualFold(filepath.Clean(registered), filepath.Clean(manifestPath)) {
		return fmt.Errorf("refusing to remove a native host registered at a different path: %s", registered)
	}
	return registry.DeleteKey(registry.CURRENT_USER, keyPath)
}
