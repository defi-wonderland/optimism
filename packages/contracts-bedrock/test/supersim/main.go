package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run . <relay_type>")
		fmt.Println("relay_type can be 'token' or 'gastank'")
		os.Exit(1)
	}

	relayType := os.Args[1]

	switch relayType {
	case "token":
		tokenRelay()
	case "gastank":
		gasTankRelay()
	default:
		fmt.Printf("Unknown relay type: %s\n", relayType)
		fmt.Println("Please use 'token' or 'gastank'")
		os.Exit(1)
	}
}
