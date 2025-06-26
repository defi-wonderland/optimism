package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run . <script_name>")
		fmt.Println("Available scripts: relay, gastank --numNestedMessages <number>")
		os.Exit(1)
	}

	gastankCmd := flag.NewFlagSet("gastank", flag.ExitOnError)
	numNestedMessages := gastankCmd.Int64("numNestedMessages", 5, "Number of nested messages to send.")

	script := os.Args[1]
	switch script {
	case "relay":
		tokenRelay()
	case "gastank":
		gastankCmd.Parse(os.Args[2:])
		gasTankRelay(*numNestedMessages)
	default:
		fmt.Printf("Unknown script: %s\n", script)
		os.Exit(1)
	}
}
